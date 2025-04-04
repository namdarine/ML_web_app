# Use Amazon Linux 2023 with Python 3.11
FROM amazonlinux:latest

# Set /app for working directory in the container
WORKDIR /app
ENV PYTHONPATH=/app/src

# Install dependencies
RUN yum update -y && yum install -y --allowerasing \
    python3.11 \
    python3.11-pip \
    python3.11-devel \
    tar \
    gzip \
    wget \
    curl \
    shadow-utils \
    java-11-amazon-corretto \
    make \
    glibc-devel \
    libstdc++ \
    libstdc++-devel \
    binutils \
    procps \
    && yum clean all

RUN alternatives --install /usr/bin/python python /usr/bin/python3.11 1

# Ensure C++ lib is reinstalled and updated
RUN yum reinstall -y libstdc++ libstdc++-devel && ldconfig

# Set Java Env
ENV JAVA_HOME=/usr/lib/jvm/java-11-amazon-corretto.x86_64
ENV PATH="${JAVA_HOME}/bin:${PATH}"

# Install Spark
RUN wget -q https://archive.apache.org/dist/spark/spark-3.5.2/spark-3.5.2-bin-hadoop3.tgz -O spark.tgz && \
    tar -xzf spark.tgz && \
    mv spark-3.5.2-bin-hadoop3 /usr/local/spark && \
    rm spark.tgz

# Set Spark environment variables
ENV SPARK_HOME=/usr/local/spark
ENV PATH=$SPARK_HOME/bin:$SPARK_HOME/sbin:$PATH
ENV PYSPARK_PYTHON=python3
ENV PYSPARK_DRIVER_PYTHON=python3

ENV SPARK_WORKER_MEMORY=2g
ENV SPARK_DRIVER_MEMORY=2g
ENV SPARK_EXECUTOR_MEMORY=2g

# Install Hadoop Native Library
RUN mkdir -p /usr/local/hadoop/lib/native && \
    wget -q https://downloads.apache.org/hadoop/common/hadoop-3.3.6/hadoop-3.3.6.tar.gz -O hadoop.tar.gz && \
    tar -xzf hadoop.tar.gz && \
    mv hadoop-3.3.6/lib/native/* /usr/local/hadoop/lib/native/ && \
    rm -rf hadoop-3.3.6 hadoop.tar.gz

# Set Hadoop environment variables
ENV HADOOP_OPTS="-Djava.library.path=/usr/local/hadoop/lib/native"
ENV LD_LIBRARY_PATH="/usr/local/hadoop/lib/native:$LD_LIBRARY_PATH"

# Hugging Face cache
ENV HF_HOME=/tmp/hf_cache
ENV HF_HUB_CACHE="/tmp/hf_cache"
ENV HF_DATASETS_CACHE="/tmp/hf_cache"
ENV TMPDIR=/var/tmp

# Upgrade pip
RUN python -m pip install --upgrade pip

# Install GCC 13.2.0
RUN yum install -y wget tar bzip2 gzip xz make gmp-devel mpfr-devel libmpc-devel

# Install essential Python libraries
ENV TMPDIR=/var/tmp
RUN python -m pip install --no-cache-dir numpy pandas scikit-learn matplotlib seaborn && \
    python -m pip install --no-cache-dir pyspark nltk peft transformers datasets accelerate einops langchain langchain-huggingface langchain-community && \
    python -m pip install --no-cache-dir gunicorn && \
    python -m pip install --no-cache-dir -U langchain-chroma langchain-huggingface && \
    rm -rf /root/.cache/pip

RUN yum install -y procps && yum clean all

# Copy all files in the current directory to /app in the container
COPY ./src /app/src
COPY ./templates /app/templates
COPY ./static /app/static
COPY requirements.txt /app/
COPY ./src/lora_train.py /app/lora_train.py

# Install remaining dependencies from requirements.txt
RUN python -m pip install --no-cache-dir -r requirements.txt && \
    rm -rf /root/.cache/pip

# Clean up unnecessary files whenever a container runs
RUN echo '#!/bin/sh' > /usr/local/bin/clean_tmp && \
    echo 'find /tmp -mindepth 1 -maxdepth 1 ! -name "hf_cache" -exec rm -rf {} +' >> /usr/local/bin/clean_tmp && \
    echo 'rm -rf /var/tmp/* /root/.cache/pip ~/.cache/pip' >> /usr/local/bin/clean_tmp && \
    chmod +x /usr/local/bin/clean_tmp

ENV HF_HUB_ENABLE_HF_XET=0

# 7. Run Flask server
CMD ["sh", "-c", "/usr/local/bin/clean_tmp && exec python3.11 -m gunicorn -w 2 -b 0.0.0.0:5000 --timeout 1200 --worker-class gthread --threads 4 src.app:app"]

#CMD ["python3.11", "/app/lora_train.py"]