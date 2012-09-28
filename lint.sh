#!/usr/bin/env bash

find . -name '*.coffee' -exec bin/coffeelint {} \;
