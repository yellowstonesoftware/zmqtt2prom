# zmqtt2prom

![Example Grafana Dashboard](https://github.com/yellowstonesoftware/zmqtt2prom/blob/main/example.png)

zmqtt2prom is a simple service to consume messages that was published to MQTT from [Zigbee2MQTT](https://www.zigbee2mqtt.io/) and expose them as [Prometheus](https://prometheus.io/) metrics over HTTP at `GET /metrics`.

## Zigbee2MQTT Support

Currently only [Generic capabilities](https://www.zigbee2mqtt.io/guide/usage/exposes.html#generic) of types binary and numeric are supported. 

On startup, the service will auto discover devices that are:
* supported 
* not disabled
* successfully interviewed by Zigbee2MQTT

## Prometheus

The following labels are added to the metrics (prefix: `mqtt2prom_(gauge|counter)`):

* friendly_name
* manufacturer
* ieee_address
* network_address
* model_id
* type
* property
* unit

## Usage

Binaries for macOS and Linux are attached to each [release](https://github.com/yellowstonesoftware/zmqtt2prom/releases) and Linux Docker containers for `arm64` and `amd64` are published to [Docker Hub](https://hub.docker.com/r/yellowstonesoftware/zmqtt2prom)

See `--help` for options but typical usage would be something like this:

```
zmqtt2prom --mqtt-host mqtt.home.com --mqtt-username myusername --mqtt-password mypassword --log-level info
```

An example [docker-compose.yml](https://github.com/yellowstonesoftware/zmqtt2prom/blob/main/docker-compose.yml) is provided otherwise the container can be ran manually:

```
docker run --rm -it --name zmqtt2prom -p 8080:8080 yellowstonesoftware/zmqtt2prom:latest --mqtt-host mqtt.home.com --mqtt-username myusername --mqtt-password mypassword --log-level info --http-port 8080
```