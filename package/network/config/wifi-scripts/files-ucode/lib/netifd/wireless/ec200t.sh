#!/usr/bin/ucode

'use strict';

import * as fs from 'fs';

const driver_name = 'ec200t';
const base_name = 'mac80211';

if (length(ARGV) < 2)
        exit(1);

let path = fs.realpath(ARGV[0]);
if (!path)
        exit(1);
let parts = split(path, '/');
parts[length(parts) - 1] = 'mac80211.sh';
let base_driver = join(parts, '/');
if (!fs.stat(base_driver))
        exit(1);

function shell_escape(str) {
        return "'" + replace(str, "'", "'\\''") + "'";
}

let args = [];
for (let i = 1; i < length(ARGV); i++)
        push(args, shell_escape(ARGV[i]));

let command = base_driver;
if (length(args))
        command += ' ' + join(args, ' ');

if (ARGV[1] == 'dump') {
        let pipe = fs.popen(command);
        if (!pipe)
                exit(1);
        let data = pipe.read('all');
        let status = pipe.close();
        if (status)
                exit(status);
        data = replace(data, '"name":"' + base_name + '"', '"name":"' + driver_name + '"');
        printf('%s', data);
        exit(0);
}

exit(system(command));
