#!/usr/bin/env python
# -*- coding: utf-8 -*

import sys
import socket
import paramiko
import bz2
import fileinput
import os
from paramiko import SSHException, PasswordRequiredException, AuthenticationException

BACKUPHOST=''
BACKUPPORT=22
USER='backups'
KEYFILE='/etc/postgresql/9.3/main/backup.key'
BACKUPPATH='/home/backups/uts24-sql-live/postgre/wal'
TEMP_PATH='/tmp'
COMPRESSION=True

class pgSSHBackup():
    def __init__(self):
        self.host = BACKUPHOST
        self.port = BACKUPPORT
        self.user = USER
        self.keyfile = KEYFILE
        self.path = BACKUPPATH
        self.ssh = paramiko.SSHClient()

    def fail(self):
        """
        Если что-то пошло не так - завершаем скрипт с кодом 1
        TODO: добавить уведомлялку
        """
        sys.exit(1)

    def success(self):
        sys.exit(0)

    def run(self):
        self.getargs()
        self.connect()
        if COMPRESSION:
            self.walcompress()
            self.walname = self.compressedname
            self.walpath = self.compressedpath
        if self.filenotexists():
            self.uploadwal()
            if COMPRESSION:
                os.remove(self.compressedpath)
            self.success()
        else:
            print 'Already uploaded'
            self.success()
#            self.fail()

    def getargs(self):
        self.walpath = sys.argv[1]
        self.walname = sys.argv[2]

    def walcompress(self):
        """
        Функция сжатия файла перед отправкой
        Как это делать налету - хз, поэтому будем складывать пожатый файлик во временную папку
        """
        self.compressedname = self.walname + '.bz2'
        self.compressedpath = TEMP_PATH + '/' + self.walname + '.bz2'
        output = bz2.BZ2File(self.compressedpath, 'wb')
        for line in fileinput.input(self.walpath):
            output.write(line)
        output.close()

    def filenotexists(self):
        """
        lstat выплевывает IOError, если файл не найден. В этом случае возращаем True
        Если файл существует - отдаем False
        """
        try:
            stats = self.sftp.lstat(self.path +'/' + self.walname)
        except IOError:
            return True
        else:
            return False

    def uploadwal(self):
        """
        Берем wal и выплевываем его на бекапник
        """
        try:
            self.sftp.put(self.walpath, self.path + '/' + self.walname)
        except IOError:
            print 'Upload error'
            self.fail()


    def connect(self):
        self.ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        try:
            self.ssh.connect(hostname=self.host, port=self.port, username=self.user, key_filename=self.keyfile)
        except IOError:
            """
            Странно, но IOError летит и в случае невозможности прицепится к хосту.
            Хотя должен выпадать socket.error
            """
            print 'Can\'t open keyfile'
            self.fail()
        except AuthenticationException:
            print 'Auth failed'
            self.fail()
        except SSHException:
            print 'Error in ssh-connect'
            self.fail()
        except socket.error:
            print 'Error connecting'
            self.fail()
        else:
            self.sftp = self.ssh.open_sftp()
            

if __name__ == '__main__':
    c = pgSSHBackup()
    c.run()

# vim: tabstop=8 expandtab shiftwidth=4 softtabstop=4
