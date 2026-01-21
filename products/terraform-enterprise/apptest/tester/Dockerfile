FROM gcr.io/cloud-marketplace-tools/testrunner:0.1.8

COPY tester.sh /tester.sh
COPY tests /tests

RUN chmod +x /tester.sh

WORKDIR /
ENTRYPOINT ["/tester.sh"]
