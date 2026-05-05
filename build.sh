#!/bin/bash
#
# Use the host network to avoid issues with SSL connections when installing Nordic tools
#

#docker build --progress=plain --network=host -t ncs-slim:v2.8.0 --build-arg SLIM=1 .
docker build --progress=plain --network=host -t ncs-full:v2.8.0 --build-arg SLIM=0 .
