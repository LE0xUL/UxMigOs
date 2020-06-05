#!/bin/bash

echo 22 > /sys/class/gpio/unexport 2>/dev/null
echo 26 > /sys/class/gpio/unexport 2>/dev/null
echo 22 > /sys/class/gpio/export
echo 26 > /sys/class/gpio/export
echo out > /sys/class/gpio/gpio22/direction
echo out > /sys/class/gpio/gpio26/direction
echo 0 > /sys/class/gpio/gpio22/value
echo 1 > /sys/class/gpio/gpio26/value
sleep 0.2
echo 0 > /sys/class/gpio/gpio26/value
echo 1 > /sys/class/gpio/gpio22/value
sleep 1
echo 0 > /sys/class/gpio/gpio22/value

exit 0