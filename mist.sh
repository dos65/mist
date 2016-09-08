#!/usr/bin/env bash

export MIST_HOME="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

read -d '' help <<- EOF
MIST – is a thin service on top of Spark which makes it possible to execute Scala & Python Spark Jobs from application layers and get synchronous, asynchronous, and reactive results as well as provide an API to external clients.

Usage:
  ./mist.sh master --config <config_file> --jar <mist_assembled_jar>

Report bugs to: https://github.com/hydrospheredata/mist/issues
Up home page: http://hydrosphere.io
EOF

if [ "$1" == "--help" ] || [ "$1" == "-h" ] || [ "$2" == "--help" ] || [ "$2" == "-h" ]
then
    echo "${help}"
    exit 0
fi

if [ "${SPARK_HOME}" == '' ] || [ ! -d "${SPARK_HOME}" ]
then
    echo "SPARK_HOME is not set"
    exit 1
fi

app=$1

shift
while [[ $# > 1 ]]
do
    key="$1"

  case ${key} in
    --runner)
      RUNNER="$2"
      shift
      ;;

    --host)
      HOST="$2"
      shift
      ;;

    --port)
      PORT="$2"
      shift
      ;;

    --namespace)
      NAMESPACE="$2"
      shift
      ;;

    --config)
      CONFIG_FILE="$2"
      shift
      ;;

    --jar)
      JAR_FILE="$2"
      shift
      ;;
  esac

shift
done

if [ "${CONFIG_FILE}" == '' ] || [ ${JAR_FILE} == '' ]
then
    echo "${help}"
    exit 1
fi
if [ "${app}" == 'worker' ]
then
    if [ "${RUNNER}" == 'local' ]
    then
        if [ "${NAMESPACE}" == '' ]
        then
            echo "You must specify --namespace to run Mist worker"
            exit 3
        fi
        ${SPARK_HOME}/bin/spark-submit --class io.hydrosphere.mist.Worker --driver-java-options "-Dconfig.file=${CONFIG_FILE}" "$JAR_FILE" ${NAMESPACE}
    elif [[ "${RUNNER}" == 'docker' ]]
    then
        # docker -H 172.17.0.1:4000 run -d --link mosquitto-$SPARK_VERSION:mosquitto hydrosphere/mist:master-$SPARK_VERSION worker ${NAMESPACE}
        export parentContainer=`curl -X GET -H "Content-Type: application/json" http://${HOST}:${PORT}/containers/$HOSTNAME/json`
        export image=`echo $parentContainer | jq -r '.Config.Image'`
        export links=`echo $parentContainer | jq -r '.HostConfig.Links'`
        export labels=`echo $parentContainer | jq -r '.Config.Labels'`
        export request="{
          \"Image\":\"$image\",
          \"Cmd\": [
            \"worker\",
            \"${NAMESPACE}\"
          ],
          \"Labels\": $labels,
          \"HostConfig\": {
            \"Links\": $links
          }
        }"
        export containerId=`curl -X POST -H "Content-Type: application/json" http://${HOST}:${PORT}/containers/create -d "$request" | jq -r '.Id'`
        curl -X POST -H "Content-Type: application/json" http://${HOST}:${PORT}/containers/$containerId/start
    fi
elif [ "${app}" == 'master' ]
then
    PID_FILE="${MIST_HOME}/master.pid"
    ${SPARK_HOME}/bin/spark-submit --class io.hydrosphere.mist.Master --driver-java-options "-Dconfig.file=${CONFIG_FILE}" "$JAR_FILE"
fi
