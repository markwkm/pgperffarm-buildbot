#!/bin/sh

BUILDBOTURL="http://147.75.56.225:8010"
CSVEXPORT="export-dbt3.csv"
CSVREPORT="report-dbt3.csv"
CSVSORTED="sorted-dbt3.csv"
PGGITDIR="/usr/local/src/postgres"
PLOTSIZE="1600,1000"

psql -X -d perffarm -o "${CSVEXPORT}" << __SQL__
COPY (
    WITH data AS (
        SELECT workers.name AS plant
             , btrim(branch.value, '"') AS branch
             , CASE WHEN revision.value = '""'
                    THEN btrim(got_revision.value, '"')
                    ELSE btrim(revision.value, '"')
                    END AS revision
             , scale.value AS scale
             , log_summary.id AS log_summary_id
             , log_test.id AS log_test_id
             , row_number() OVER (
                   PARTITION BY workers.name
                              , branch.value
                              , revision
                              , scale.value
                   ORDER BY builds.complete_at DESC
               ) AS latest
        FROM workers
             JOIN builds
               ON builds.workerid = workers.id
              AND builds.results = 0
             JOIN builders
               ON builders.id = builderid
             JOIN build_properties AS branch
               ON branch.buildid = builds.id
              AND branch.name = 'branch'
              AND branch.value <> '""'
             JOIN build_properties AS revision
               ON revision.buildid = builds.id
              AND revision.name = 'revision'
             JOIN build_properties AS got_revision
               ON got_revision.buildid = builds.id
              AND got_revision.name = 'got_revision'
             LEFT OUTER JOIN build_properties AS scale
               ON scale.buildid = builds.id
              AND scale.name = 'scale'
             JOIN steps AS step_summary
               ON step_summary.buildid = builds.id
              AND step_summary.name = 'DBT-3 Metrics'
             JOIN logs AS log_summary
               ON log_summary.stepid = step_summary.id
             LEFT OUTER JOIN steps AS step_test
               ON step_test.buildid = builds.id
              AND step_test.name = 'Performance test'
             LEFT OUTER JOIN logs AS log_test
               ON log_test.stepid = step_test.id
        WHERE builders.name = 'dbt3'
          OR builders.name LIKE 'dbt3-%'
    )
    SELECT plant
         , branch
         , revision
         , scale
         , log_summary_id
         , log_test_id
    FROM data
    WHERE latest = 1
)
TO STDOUT
(FORMAT csv, HEADER TRUE, DELIMITER ' ', NULL 'NULL');
__SQL__

HEADER="$(head -n 1 "${CSVEXPORT}") ctime metric sf load power throughput"

(cd "${PGGITDIR}" && git fetch -q --all && git pull -q)

echo "${HEADER}" > "${CSVREPORT}"
tail -n +2 "${CSVEXPORT}" | while IFS= read -r LINE; do
	COMMIT="$(echo "${LINE}" | cut -d " " -f 3)"
	SCALE="$(echo "${LINE}" | cut -d " " -f 4)"
	LOGSUMMARY="$(echo "${LINE}" | cut -d " " -f 5)"
	LOGTEST="$(echo "${LINE}" | cut -d " " -f 6)"

	CTIME="$(cd "${PGGITDIR}" && git show -s --format="%ct" "${COMMIT}")"

	METRICS="$(curl --silent \
			"${BUILDBOTURL}/api/v2/logs/${LOGSUMMARY}/raw_inline")"

	SCORE="$(echo "${METRICS}" | \
			sed -n \
			's/.*Composite Score:[ ]\+\([0-9]\+\(\.[0-9]\+\)\?\).*/\1/p')"

	LOAD="$(echo "${METRICS}" | \
			sed -n \
			's/.*Load Test Time (hours):[ ]*\([0-9.]\+\).*/\1/p')"

	POWER="$(echo "${METRICS}" | \
			sed -n \
			's/.*Power Test Score:[ ]\+\([0-9]\+\(\.[0-9]\+\)\?\).*/\1/p')"

	THROUGHPUT="$(echo "${METRICS}" | \
			sed -n \
			's/.*Throughput Test Score:[ ]\+\([0-9]\+\(\.[0-9]\+\)\?\).*/\1/p')"

	if [ "${SCALE}" = "NULL" ]; then
		SF="$(curl --silent "${BUILDBOTURL}/api/v2/logs/${LOGTEST}/raw_inline" \
				| sed -n 's/.*SCALE: \([0-9]\+\(\.[0-9]\+\)\?\).*/\1/p')"
	else
		SF="${SCALE}"
	fi

	echo "${LINE} ${CTIME} ${SCORE} ${SF} ${LOAD} ${POWER} ${THROUGHPUT}" >> \
			"${CSVREPORT}"
done

tail -n +2 "${CSVREPORT}" | sort -t " " -k 7 -n > "${CSVSORTED}"

BRANCHES="$(tail -n +2 "${CSVEXPORT}" | cut -d " " -f 2 | sort -u | xargs)"
PLANTS="$(tail -n +2 "${CSVEXPORT}" | cut -d " " -f 1 | sort -u | xargs)"
SCALES="$(tail -n +2 "${CSVSORTED}" | cut -d " " -f 9 | sort -u | xargs)"

TMPFILELIST=""
for SCALE in ${SCALES}; do
	TMPFILESCALE="$(mktemp)"
	TMPFILELIST="${TMPFILELIST} ${TMPFILESCALE}"
	awk -F " " "\$9 == \"${SCALE}\"" "${CSVSORTED}" >> "${TMPFILESCALE}"

	for PLANT in ${PLANTS}; do
		COUNT=0
		PLOTLIST=""
		PLOTLISTLOAD=""
		PLOTLISTPOWER=""
		PLOTLISTTHROUGHPUT=""
		TMPFILELIST=""
		for BRANCH in ${BRANCHES}; do
			TMPFILE="$(mktemp)"
			TMPFILELIST="${TMPFILELIST} ${TMPFILE}"

			echo "${HEADER}" > "${TMPFILE}"
			awk -F " " "\$1 == \"${PLANT}\" && \$2 == \"${BRANCH}\"" \
					"${TMPFILESCALE}" >> "${TMPFILE}"

			COUNT=$(( COUNT + 1 ))
			if [ ${COUNT} -gt 1 ]; then
				PLOTLIST="${PLOTLIST},"
				PLOTLISTLOAD="${PLOTLISTLOAD},"
				PLOTLISTPOWER="${PLOTLISTPOWER},"
				PLOTLISTTHROUGHPUT="${PLOTLISTTHROUGHPUT},"
			fi
			PLOTLIST="${PLOTLIST}'${TMPFILE}' using 'ctime':'metric' title '${BRANCH}' noenhanced with linespoints"
			PLOTLISTLOAD="${PLOTLISTLOAD}'${TMPFILE}' using 'ctime':'load' title '${BRANCH}' noenhanced with linespoints"
			PLOTLISTPOWER="${PLOTLISTPOWER}'${TMPFILE}' using 'ctime':'power' title '${BRANCH}' noenhanced with linespoints"
			PLOTLISTTHROUGHPUT="${PLOTLISTTHROUGHPUT}'${TMPFILE}' using 'ctime':'throughput' title '${BRANCH}' noenhanced with linespoints"
		done

		plot()
		{
			NAME="${1}"
			TITLE="${2}"
			LABEL="${3}"
			LINES="${4}"

			gnuplot <<- __PLOT__
				set xdata time
				set timefmt "%s"
				set terminal pngcairo size ${PLOTSIZE}
				set xlabel "Time"
				set xtics rotate
				set xtics format "%Y-%m-%d"
				set grid
				set title "DBT-3 ${TITLE}Results ${PLANT} Scale Factor ${SCALE}" noenhanced
				set output 'dbt3-${PLANT}-${SCALE}${NAME}.png'
				set ylabel "${LABEL}"
				set yrange [0:*]
				set key below
				plot ${LINES}
			__PLOT__
		}

		plot "" "" "Composite Score" "${PLOTLIST}"
		plot "-load" "Load " "Hours" "${PLOTLISTLOAD}"
		plot "-power" "Power " "Power Score" "${PLOTLISTPOWER}"
		plot "-throughput" "Throughput " "Throughput Score" "${PLOTLISTTHROUGHPUT}"
	done
done

echo "${TMPFILELIST}" | xargs rm
