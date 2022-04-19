FROM python:3-slim

ARG MLFLOW_PORT_NUM
ENV MLFLOW_PORT=$MLFLOW_PORT_NUM
ARG ARTIFACT_ROOT_PATH
ENV ARTIFACT_ROOT=$ARTIFACT_ROOT_PATH
ARG BACKEND_URI_PATH
ENV BACKEND_URI=${BACKEND_URI_PATH:-sqlite:///my.db}


WORKDIR /mlflow/
COPY requirements.txt /tmp
RUN pip install -r /tmp/requirements.txt

CMD mlflow server --backend-store-uri ${BACKEND_URI} --default-artifact-root ${ARTIFACT_ROOT} --host 0.0.0.0 --port ${MLFLOW_PORT}