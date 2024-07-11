#!/bin/sh

BUILDBOTURL="http://147.75.56.225:8010"
CSVEXPORT="export-dbt7.csv"
CSVREPORT="report-dbt7.csv"
CSVSORTED="sorted-dbt7.csv"
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
              AND step_summary.name = 'DBT-7 Summary'
             JOIN logs AS log_summary
               ON log_summary.stepid = step_summary.id
        WHERE builders.name = 'dbt7'
          OR builders.name LIKE 'dbt7-%'
    )
    SELECT plant
         , branch
         , revision
         , scale
         , log_summary_id
    FROM data
    WHERE latest = 1
)
TO STDOUT
(FORMAT csv, HEADER TRUE, DELIMITER ' ', NULL 'NULL');
__SQL__

HEADER="$(head -n 1 "${CSVEXPORT}") ctime metric"

(cd "${PGGITDIR}" && git fetch -q --all && git pull -q)

echo "${HEADER} " > "${CSVREPORT}"
tail -n +2 "${CSVEXPORT}" | while IFS= read -r LINE; do
	COMMIT="$(echo "${LINE}" | cut -d " " -f 3)"
	SCALE="$(echo "${LINE}" | cut -d " " -f 4)"
	LOGSUMMARY="$(echo "${LINE}" | cut -d " " -f 5)"

	CTIME="$(cd "${PGGITDIR}" && git show -s --format="%ct" "${COMMIT}")"

	SUMMARY="$(curl --silent "${BUILDBOTURL}/api/v2/logs/${LOGSUMMARY}/raw_inline")"
	SCORE="$(echo "${SUMMARY}"| \
			sed -n 's/.*Queries per Hour:[ ]\+\([0-9]\+\?\).*/\1/p')"

	if [ "${SCALE}" = "NULL" ]; then
		SF="$(echo "${SUMMARY}"| sed -n 's/.*Scale:[ ]\+\([0-9]\+\?\).*/\1/p')"
	else
		SF="${SCALE}"
	fi

	echo "${LINE} ${CTIME} ${SCORE} ${SF}" >> "${CSVREPORT}"
done

tail -n +2 "${CSVREPORT}" | sort -t " " -k 6 -n > "${CSVSORTED}"

BRANCHES="$(tail -n +2 "${CSVEXPORT}" | cut -d " " -f 2 | sort -u | xargs)"
PLANTS="$(tail -n +2 "${CSVEXPORT}" | cut -d " " -f 1 | sort -u | xargs)"
SCALES="$(tail -n +2 "${CSVSORTED}" | cut -d " " -f 8 | sort -u | xargs)"

TMPFILELIST=""
for SCALE in ${SCALES}; do
	TMPFILESCALE="$(mktemp)"
	TMPFILELIST="${TMPFILELIST} ${TMPFILESCALE}"
	awk -F " " "\$8 == \"${SCALE}\"" "${CSVSORTED}" >> "${TMPFILESCALE}"

	for PLANT in ${PLANTS}; do
		COUNT=0
		PLOTLIST=""
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
			fi
			PLOTLIST="${PLOTLIST}'${TMPFILE}' using 'ctime':'metric' title '${BRANCH}' noenhanced with linespoints"
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
				set title "DBT-7 ${TITLE}Results ${PLANT} Scale Factor ${SCALE}" noenhanced
				set output 'dbt7-${PLANT}-${SCALE}${NAME}.png'
				set ylabel "${LABEL}"
				set yrange [0:*]
				set key below
				plot ${LINES}
			__PLOT__
		}

		plot "" "" "Queries / Hour" "${PLOTLIST}"
	done
done

echo "${TMPFILELIST}" | xargs rm
