# zmqtt2prom

![Example Grafana Dashboard](https://github.com/yellowstonesoftware/zmqtt2prom/blob/main/example.png)

zmqtt2prom is a simple service to consume messages that was published to MQTT from [Zigbee2MQTT](https://www.zigbee2mqtt.io/) and expose them as [Prometheus](https://prometheus.io/) metrics over HTTP at `GET /metrics`.

Currently only [Generic capabilities](https://www.zigbee2mqtt.io/guide/usage/exposes.html#generic) of types binary and numeric are supported. 

On startup, the service will auto discover devices that are:
* supported 
* not disabled
* successfully interviewed by Zigbee2MQTT

See `--help` for options but typical usage would be something like this:

```
zmqtt2prom --mqtt-host mqtt.home.com --mqtt-username myusername --mqtt-password mypassword --log-level info
```

Building with docker

```
# Build the Docker image
docker build -t zmqtt2prom:latest .
```

Running with docker

```
docker run --rm -it  -n zmqtt2prom -p 8080:8080 zmqtt2prom:latest  --mqtt-host mqtt.home.com --mqtt-username myusername --mqtt-password mypassword --log-level info

```

The following labels are added to the metrics (prefix: `mqtt2prom`):

* friendly_name
* manufacturer
* ieee_address
* network_address
* model_id
* type
* property
* unit
