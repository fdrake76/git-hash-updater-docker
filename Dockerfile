FROM debian:10

RUN apt-get update && \
	apt-get install -y jq git && \
	rm -rf /var/lib/apt/lists/*
ADD update-repo.sh /

VOLUME /data

CMD ["/update-repo.sh"]
