echo off
%~d0
cd %~p0
set STUNNELBIN = ..\bin
set PATH=%STUNNELBIN%;%PATH%;
stunnel -install -quiet
stunnel -start -quiet
stunnel -reload -quiet