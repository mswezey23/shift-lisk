FROM node:10-alpine
LABEL description="Shift Core Docker Image" version="1.0.0"

ENV MUSL_LOCPATH="/usr/share/i18n/locales/musl"
ENV PGDATA="/var/lib/postgresql/data"

# see https://github.com/gliderlabs/docker-alpine/issues/437#issuecomment-494200575
VOLUME [ “/sys/fs/cgroup” ]

# Install Essentials
WORKDIR /~
RUN apk update
RUN apk add --virtual build-dependencies openrc make postgresql-dev g++ build-base gcc wget musl-dev gettext-dev \
    git bash libtool autoconf automake python postgresql postgresql-contrib libpq openntpd cmake

# Locales for postgresql
RUN git clone https://gitlab.com/rilian-la-te/musl-locales.git && \
	cd musl-locales && cmake -DLOCALE_PROFILE=OFF -DCMAKE_INSTALL_PREFIX:PATH=/usr . && make && make install && \
	cd .. && rm -r musl-locales
# RUN update-rc.d postgresql enable
# RUN ntpdate pool.ntp.org
# RUN openntpd start

# Create shift user & group
RUN addgroup -S shift && adduser -S -D shift -G shift
RUN addgroup shift postgres
USER shift
WORKDIR /home/shift

# Configure Global NPM Folder
RUN mkdir /home/shift/.npm-global
RUN npm config set prefix "~/.npm-global"
RUN export PATH=~/.npm-global/bin:$PATH

# Copy Assets
COPY --chown=shift:shift . /home/shift
# Overwrite Ubuntu Bash Script with Docker Bash Script
ADD --chown=shift:shift scripts/shift_manager.bash /home/shift/shift_manager.bash
RUN ls -la

# Install Shift Core
# RUN npm install --production
# RUN ./shift_manager.bash install
USER root
RUN ls -la
RUN mkdir /var/lib/postgresql/data &&\
    mkdir /var/run/postgresql
RUN chown -R shift:shift /var/lib/postgresql &&\
    chown -R shift:shift /var/run/postgresql

# RUN initdb /var/lib/postgresql/data &&\
#     echo "host all all 0.0.0.0/0 md5" >> /var/lib/postgresql/data/pg_hba.conf &&\
#     echo "listen_addresses='*'" >> /var/lib/postgresql/data/postgresql.conf &&\
#     pg_ctl start &&\
#     psql -U shift -tc "SELECT 1 FROM pg_database WHERE datname = 'main'" | grep -q 1 || psql -U shift -c "CREATE DATABASE main" &&\
#     psql --command "ALTER USER postgres WITH ENCRYPTED PASSWORD 'mysecurepassword';"

    # psql -c "CREATE DATABASE 'shift_db'"

# RUN psql -c "DROP DATABASE shift_db"
 RUN /etc/init.d/postgresql status


## Install Shift Wallet
# RUN npm install forever -g
# RUN npm install bower -g
# RUN npm install grunt-cli -g
# RUN git clone https://github.com/mswezey23/shift-wallet
# RUN rm -rf public/
# RUN mv shift-wallet public
# RUN cd public && npm install
# RUN cd public && npx bower install
# RUN cd public && npx grunt release

# Configure PostgreSQL
# RUN /etc/init.d/postgresql start && \
#     sudo -u postgres createuser --createdb shift && \
#     sudo -u postgres psql -c "ALTER USER \"shift\" WITH PASSWORD 'password';" && \
#     sudo -u postgres createdb -O shift shift_test

ENV TOP=true
ENV TERM=xterm

EXPOSE 9305
ENTRYPOINT ./shift_manager start