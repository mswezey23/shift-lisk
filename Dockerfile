# Base Ubuntu 18.04 
FROM ubuntu:bionic as base
LABEL description="Shift Core Docker Image" version="1.0.0"

ARG DEBIAN_FRONTEND=noninteractive
ENV PGDATA="/var/lib/postgresql/data"
ENV NPM_CONFIG_PREFIX=/home/shift/.npm-global
ENV PATH=$PATH:/home/shift/.npm-global/bin 
# optionally if you want to run npm global bin without specifying path

# Install Dependencies
WORKDIR /~
RUN apt-get update && apt-get upgrade -y
RUN apt-get install -y locales curl build-essential python lsb-release wget ntp\
    openssl autoconf libtool automake libsodium-dev jq dnsutils gcc g++ make git sudo
# &&\ service ntp stop && ntpdate pool.ntp.org && service ntp start

# Install Postgres
RUN bash -c 'echo "deb http://apt.postgresql.org/pub/repos/apt/ wheezy-pgdg main" > /etc/apt/sources.list.d/pgdg.list' &&\
    wget -q https://www.postgresql.org/media/keys/ACCC4CF8.asc -O - | apt-key add - &&\
    apt-get update && apt-get install -y postgresql-9.6 postgresql-contrib-9.6 libpq-dev &&\
    update-rc.d postgresql enable

# Adjust PostgreSQL configuration so that remote connections to the database are possible.
RUN echo "host all  all    0.0.0.0/0  md5" >> /etc/postgresql/9.6/main/pg_hba.conf

# And add ``listen_addresses`` to ``/etc/postgresql/9.6/main/postgresql.conf``
RUN echo "listen_addresses='*'" >> /etc/postgresql/9.6/main/postgresql.conf

# Install Node 10.X
RUN curl -sL https://deb.nodesource.com/setup_10.x | bash - &&\
    apt-get install -y -qq nodejs


FROM base AS shiftuser
# Create shift user & group
RUN useradd -ms /bin/bash shift
RUN addgroup shift postgres && addgroup shift ssl-cert
RUN echo "LC_ALL=en_US.UTF-8" >> /etc/environment &&\
    echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen &&\
    echo "LANG=en_US.UTF-8" > /etc/locale.conf
RUN locale-gen en_US.UTF-8

# Configure Global NPM Folder
USER shift
WORKDIR /home/shift
RUN mkdir .npm-global
RUN npm config set prefix "~/.npm-global"
RUN export PATH=~/.npm-global/bin:$PATH && /bin/bash -c "source ~/.profile"
RUN npm install -g forever
RUN npm install -g bower
RUN npm install -g grunt-cli


FROM shiftuser as shiftcore
USER shift
WORKDIR /home/shift
# Copy Assets
COPY --chown=shift:shift . /home/shift/
# Overwrite Ubunti Bash Script with Docker Bash Script
ADD --chown=shift:shift scripts/shift_manager.bash /home/shift/shift_manager.bash
RUN ls -la

# Install Shift Core
USER postgres
RUN /etc/init.d/postgresql start && psql -c "CREATE USER shift WITH SUPERUSER PASSWORD 'testing';" &&\
    createdb -O shift shift_db && /etc/init.d/postgresql stop
# && ./shift_manager.bash install

USER shift
WORKDIR /home/shift
RUN npm install --production


FROM shiftcore as shiftwallet
USER shift
WORKDIR /home/shift
## Install Shift Wallet
RUN git clone https://github.com/mswezey23/shift-wallet
RUN rm -rf public/
RUN mv shift-wallet public
RUN cd public && npm install
RUN cd public && npx bower install
RUN cd public && npx grunt release

ENV TOP=true
ENV TERM=xterm

EXPOSE 5432
EXPOSE 9305
USER root
RUN chown -R shift:shift /var/lib/postgresql &&\
    chown -R shift:shift /var/run/postgresql &&\
    chown -R shift:shift /etc/postgresql 
USER shift
WORKDIR /home/shift
ENTRYPOINT ./shift_manager.bash start
#CMD ["/usr/lib/postgresql/9.6/bin/postgres", "-D", "/var/lib/postgresql/9.6/main", "-c", "config_file=/etc/postgresql/9.6/main/postgresql.conf"]