#!/usr/bin/env python3
# -*- coding: utf-8 -*-

# -------------------------------------------------------------------------------------------------------------------- #
"""
 Detect and automagically rip media from optical drives

 The MIT License (MIT)

 Copyright © 2020 by John Celoria.

 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in all
 copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 SOFTWARE.

"""
# Library imports ---------------------------------------------------------------------------------------------------- #
from pathlib import Path
import asyncio
import cdio
import configparser
import itertools
import logging.handlers
import os
import pycdio
import pyudev
import re
import signal
import sys

# Set some defaults -------------------------------------------------------------------------------------------------- #
__author__ = 'John Celoria'
__version__ = '0.1'

# The location of the configuration file
SETTINGS = os.environ.get('RIPPER_SETTINGS') or '/ripper/settings.conf'

# Ripped files will be owned by the following user/group
USER_ID = os.environ.get('USER_ID') or 'nobody'
GROUP_ID = os.environ.get('GROUP_ID') or 'users'

# Read the configuration file ---------------------------------------------------------------------------------------- #
CONFIG = configparser.ConfigParser()
try:
    with open(SETTINGS) as fh:
        CONFIG.read_file(itertools.chain(['[global]'], fh), source=SETTINGS)
        CONFIG = CONFIG['global']
finally:
    fh.close()

# Setup logging ------------------------------------------------------------------------------------------------------ #
log = logging.getLogger(__name__)
log.setLevel(logging.INFO)

# Suppress less than WARNING level messages for the request module
logging.getLogger("requests").setLevel(logging.WARNING)

# Default logging format
log_format = '[%(filename)s:%(funcName)s]: %(levelname)s - %(message)s'

# File logging
fh = logging.FileHandler(Path(CONFIG.get('app_DestinationDir').strip('"'), 'ripper.log'))
fh.setLevel(logging.INFO)
fh.setFormatter(logging.Formatter('%(asctime)s ' + log_format))
log.addHandler(fh)

# Also log to the console (stderr by default)
ch = logging.StreamHandler(sys.stdout)
ch.setLevel(logging.INFO)
ch.setFormatter(logging.Formatter('%(asctime)s ' + log_format))
log.addHandler(ch)


# Functions ---------------------------------------------------------------------------------------------------------- #
def get_drives():
    try:
        return cdio.get_devices_with_cap(pycdio.FS_MATCH_ALL, False)
    except IOError:
        log.critical("Problem finding any CD-ROMs")
        sys.exit(1)


# -------------------------------------------------------------------------------------------------------------------- #
def get_status():
    status = [s.strip().split(',') for s in os.popen('makemkvcon -r --cache=1 info disc:').readlines()]
    drives = [s for s in status if re.search(r'DRV:\d+', s[0]) and s[1] != '256']

    states = {
        '0': {'0': 'empty'},
        '1': {'0': 'open'},
        '2': {'0': 'audio',
              '1': 'dvd',
              '12': 'bd',
              '28': 'bd'},
        '3': {'0': 'loading'}
    }

    # Append inserted media state to the output of the drive status
    for d in drives:
        d.append(states.get(d[1]).get(d[3], 'unknown'))

    # Strip quotes from the output of makemkvcon and return a list of dictionaries
    keys = ['index', 'visible', 'enabled', 'state', 'name', 'label', 'device', 'media']
    return [{k: v.strip('\"') for k, v in zip(keys, d)} for d in drives]


# -------------------------------------------------------------------------------------------------------------------- #
def rip_audio():
    log.info('ripping audio!')


# -------------------------------------------------------------------------------------------------------------------- #
def rip_video():
    log.info('ripping video!')


# -------------------------------------------------------------------------------------------------------------------- #
def get_property(device, key):
    return device.properties[key]


# -------------------------------------------------------------------------------------------------------------------- #
def iter_properties(device):
    for key in device.properties:
        yield key


# -------------------------------------------------------------------------------------------------------------------- #
def on_uevent(action, device, source, cache):
    log.info('{} {} ({})'.format(source, device.sys_path, device.subsystem))

    properties = {}
    for key in iter_properties(device):
        properties[key] = get_property(device, key)
        cache[device.sys_path] = properties

    status = next((item for item in get_status() if item["device"] == properties.get('DEVNAME')), None)
    device, media = status.get('device'), status.get('media')
    log.info('"{}" device changed to "{}"'.format(device, media))

    if media == 'dvd' or media == 'bd':
        log.info('<insert ripping {} command here>'.format(media))
    elif media == 'audio':
        log.info('<insert ripping {} command here>'.format(media))
    elif media == 'open':
        log.info('Your media was ejected')
    else:
        log.critical('What am I supposed to do with "{}"?'.format(media))


# -------------------------------------------------------------------------------------------------------------------- #
def reader(monitor, source, cache):
    action, device = monitor.receive_device()
    on_uevent(action, device, source, cache)


# -------------------------------------------------------------------------------------------------------------------- #
def signal_handler(signal_name):
    log.info('got %s', signal_name)
    asyncio.get_event_loop().stop()


# main --------------------------------------------------------------------------------------------------------------- #
def main():
    log.info('Found devices: {}'.format(get_drives()))

    context = pyudev.Context()
    loop = asyncio.get_event_loop()

    monitor = pyudev.Monitor.from_netlink(context, 'kernel')
    monitor.filter_by('block')

    cache = {}
    loop.add_reader(monitor, reader, monitor, 'kernel', cache)
    monitor.start()

    loop.add_signal_handler(signal.SIGINT, signal_handler, 'SIGINT')
    loop.add_signal_handler(signal.SIGTERM, signal_handler, 'SIGTERM')

    loop.run_forever()
    loop.close()

    logging.shutdown()


if __name__ == '__main__':
    sys.tracebacklimit = 0
    try:
        main()
    except KeyboardInterrupt:
        log.info('Interrupted!')
        try:
            sys.exit(0)
        except SystemExit:
            os._exit(0)

# -------------------------------------------------------------------------------------------------------------------- #
