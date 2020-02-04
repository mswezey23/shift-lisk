# Base Ubuntu 18.04 
FROM ubuntu:bionic as base
LABEL description="Shift Core Docker Image" version="1.0.0"

ARG DEBIAN_FRONTEND=noninteractive
ENV TOP=true
ENV TERM=xterm
ENV NPM_CONFIG_PREFIX=/home/shift/.npm-global
ENV PATH=$PATH:/home/shift/.npm-global/bin 
# optionally if you want to run npm global bin without specifying path

# Install Dependencies
WORKDIR /~
RUN apt-get update && apt-get upgrade -y &&\
    apt-get install -y locales curl build-essential python lsb-release wget ntp \
    openssl autoconf libtool automake libsodium-dev jq dnsutils gcc g++ make git libpq-dev

# Install Node 10.X
RUN curl -sL https://deb.nodesource.com/setup_10.x | bash - &&\
    apt-get install -y nodejs


FROM base AS shiftuser
# Create shift user & group
RUN useradd -ms /bin/bash shift
RUN echo "LC_ALL=en_US.UTF-8" >> /etc/environment &&\
    echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen &&\
    echo "LANG=en_US.UTF-8" > /etc/locale.conf &&\
    locale-gen en_US.UTF-8

# Configure Global NPM Folder
USER shift
WORKDIR /home/shift
RUN mkdir .npm-global && npm config set prefix "~/.npm-global" &&\ 
    export PATH=~/.npm-global/bin:$PATH && /bin/bash -c "source ~/.profile" &&\
    npm install -g forever bower grunt-cli

# Install Shift Core
FROM shiftuser as shiftcore
USER shift
WORKDIR /home/shift
# Copy Assets
COPY ./package.json .
# COPY ./package-lock.json .
RUN npm install --production
COPY --chown=shift:shift . .

# Install Shift Wallet
FROM shiftcore as shiftwallet
USER shift
WORKDIR /home/shift/shift-wallet
# RUN git clone https://github.com/mswezey23/shift-wallet && rm -rf public/ && mv shift-wallet public &&\ 
#     cd public && npm install && bower install && grunt release

# Copy Assets
COPY ./shift-wallet/package.json .
# COPY ./shift-wallet/package-lock.json .
RUN npm install && bower install && grunt release
COPY --chown=shift:shift ./shift-wallet/ .

## Waits for SERVICE to be running (ping via port) before continuing
USER root
ADD https://github.com/ufoscout/docker-compose-wait/releases/download/2.2.1/wait /wait
RUN chmod +x /wait

USER shift
WORKDIR /home/shift
EXPOSE 9305
CMD /wait && npm start