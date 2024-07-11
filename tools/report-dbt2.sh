#!/bin/sh

BUILDBOTURL="http://147.75.56.225:8010"
CSVEXPORT="export-dbt2.csv"
CSVREPORT="report-dbt2.csv"
CSVSORTED="sorted-dbt2.csv"
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
              AND scale.name = 'warehouses'
             JOIN steps AS step_summary
               ON step_summary.buildid = builds.id
              AND step_summary.name = 'DBT-2 Summary'
             JOIN logs AS log_summary
               ON log_summary.stepid = step_summary.id
             LEFT OUTER JOIN steps AS step_test
               ON step_test.buildid = builds.id
              AND step_test.name = 'Performance test'
             LEFT OUTER JOIN logs AS log_test
               ON log_test.stepid = step_test.id
        WHERE builders.name = 'dbt2'
          OR builders.name LIKE 'dbt2-%'
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

HEADER="$(head -n 1 "${CSVEXPORT}") ctime metric warehouses"

(cd "${PGGITDIR}" && git fetch -q --all && git pull -q)

echo "${HEADER}" > "${CSVREPORT}"
tail -n +2 "${CSVEXPORT}" | while IFS= read -r LINE; do
	COMMIT="$(echo "${LINE}" | cut -d " " -f 3)"
	SCALE="$(echo "${LINE}" | cut -d " " -f 4)"
	LOGSUMMARY="$(echo "${LINE}" | cut -d " " -f 5)"
	LOGTEST="$(echo "${LINE}" | cut -d " " -f 6)"

	CTIME="$(cd "${PGGITDIR}" && git show -s --format="%ct" "${COMMIT}")"

	NOTPM="$(curl --silent "${BUILDBOTURL}/api/v2/logs/${LOGSUMMARY}/raw_inline" \
			| sed -n 's/.*Throughput: \([0-9]\+\(\.[0-9]\+\)\?\).*/\1/p')"

	if [ "${SCALE}" = "NULL" ]; then
		WAREHOUSES="$(curl --silent "${BUILDBOTURL}/api/v2/logs/${LOGTEST}/raw_inline" \
				| sed -n 's/.*SCALE FACTOR (WAREHOUSES): \([0-9]\+\(\.[0-9]\+\)\?\).*/\1/p')"
	else
		WAREHOUSES="${SCALE}"
	fi

	echo "${LINE} ${CTIME} ${NOTPM} ${WAREHOUSES}" >> "${CSVREPORT}"
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
		for BRANCH in ${BRANCHES}; do
			TMPFILE="$(mktemp)"
			TMPFILELIST="${TMPFILELIST} ${TMPFILE}"

			echo "${HEADER}" > "${TMPFILE}"
			awk -F " " "\$1 == \"${PLANT}\" && \$2 == \"${BRANCH}\"" \
					"${TMPFILESCALE}" >> "${TMPFILE}"

			LINES="$(wc -l "${TMPFILE}" | cut -d " " -f 1)"
			if [ "${LINES}" -eq 1 ]; then
				continue
			fi

			COUNT=$(( COUNT + 1 ))
			if [ ${COUNT} -gt 1 ]; then
				PLOTLIST="${PLOTLIST},"
			fi
			PLOTLIST="${PLOTLIST}'${TMPFILE}' using 'ctime':'metric' title '${BRANCH}' noenhanced with linespoints"
		done

		gnuplot <<- __PLOT__
			set xdata time
			set timefmt "%s"
			set terminal pngcairo size ${PLOTSIZE}
			set xlabel "Time"
			set xtics rotate
			set xtics format "%Y-%m-%d"
			set grid
			set title "DBT-2 Results ${PLANT} ${SCALE} Warehouses" noenhanced
			set output 'dbt2-${PLANT}-${SCALE}.png'
			set ylabel "New Orders / Minute"
			set yrange [0:*]
			set key below
			plot ${PLOTLIST}
		__PLOT__
	done
done

echo "${TMPFILELIST}" | xargs rm
