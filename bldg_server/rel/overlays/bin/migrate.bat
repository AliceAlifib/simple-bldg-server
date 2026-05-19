@echo off
cd %~dp0
call bldg_server eval BldgServer.Release.migrate
