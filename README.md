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

### Metrics

| Metric | Labels | Meaning |
| --- | --- | --- |
| `mqtt2prom_gauge` | `friendly_name`, `manufacturer`, `ieee_address`, `model_id`, `type`, `property`, `unit` | One series per device property, for numeric and binary exposes |
| `mqtt2prom_device_info` | `friendly_name`, `manufacturer`, `ieee_address`, `model_id`, `type` | Always `1`. One per discovered device |
| `mqtt2prom_device_last_message_timestamp_seconds` | `friendly_name`, `ieee_address` | When a message from this device was last received |
| `mqtt2prom_mqtt_connected` | — | `1` while the MQTT session is up |

### Monitoring your monitoring

Two behaviours are worth understanding before you write alerting rules against this
exporter, because both make the obvious rule wrong.

**Readings do not expire.** A device that stops reporting keeps its last value
exported at every scrape, indefinitely. That is usually what you want on a dashboard,
but it means `absent()` and staleness rules can never detect a dead sensor — a water
leak sensor whose battery dies keeps reporting "dry" forever. Use the message
timestamp instead:

```promql
# A device that has not been heard from in six hours
time() - mqtt2prom_device_last_message_timestamp_seconds > 6 * 3600
```

**Event-driven devices have no series until triggered.** IAS Zone devices — water
leak, contact and motion sensors — transmit only on state change, so a newly paired
one produces no `mqtt2prom_gauge` at all until something physically sets it off. It is
invisible rather than idle. `mqtt2prom_device_info` is published at discovery, so:

```promql
# Known to Zigbee2MQTT but has never sent a message
mqtt2prom_device_info unless on (ieee_address) mqtt2prom_device_last_message_timestamp_seconds
```

Also note that `up` on this exporter's scrape target is not a health signal: the HTTP
server keeps serving cached gauges after the broker connection drops. Alert on
`mqtt2prom_mqtt_connected == 0` instead.

### Renames

`friendly_name` is a label, so renaming a device in Zigbee2MQTT produces a new label
set. The old one is unregistered when the rename is seen, on the next `bridge/devices`
message or the device's next reading — whichever arrives first. Devices removed from
the network have all their series dropped at the next discovery.

This is a behaviour change: before, a renamed device kept exporting its previous name
frozen at its last value forever. If you were relying on that persistence, note that
it also made staleness detection impossible.

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