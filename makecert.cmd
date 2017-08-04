echo off
%~d0
cd %~p0
set STUNNELBIN = ..\bin
set PATH=%STUNNELBIN%;%PATH%;

rem // Первый вызов openssl создаст ключ и корневой сертификат в формате PEM
rem // openssl попросит пользователя задать пароль, которым будет защищён ключ и при каждой новой подписи сертификата шлюза этот пароль потребуется

rem // Второй вызов openssl конвертирует сертификат из PEM в DER формат понятный Windows
rem // Корневой сертификат в PEM формате понадобится для Firefox

if not exist "rootkey.pem" (
 echo [ req ]                                             >openssl.root.cnf
 echo distinguished_name = req_distinguished_name         >>openssl.root.cnf

 echo [v3_ca]                                             >>openssl.root.cnf
 echo subjectKeyIdentifier = hash                         >>openssl.root.cnf
 echo authorityKeyIdentifier = keyid:always,issuer:always >>openssl.root.cnf
 echo basicConstraints = critical, CA:TRUE                >>openssl.root.cnf
 echo keyUsage = keyCertSign, cRLSign                     >>openssl.root.cnf

 echo [ req_distinguished_name ]                          >>openssl.root.cnf

 openssl.exe req -newkey rsa:4096 -x509 -sha256 -days 5480 -config openssl.root.cnf -extensions v3_ca -utf8 -subj "/CN=127.0.0.1" -out rootcert.pem -keyout rootkey.pem

 openssl.exe x509 -outform der -in rootcert.pem -out rootcert.crt

 del openssl.root.cnf
)

rem // Теперь создаём ключ который будет использоваться шлюзом

if not exist "gatewaykey.pem" (
 openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out gatewaykey.pem
)

rem // Делаем запрос сертификата шлюза

if not exist "gateway.csr" (

 echo [ req ]                                                      >openssl.req.cnf
 echo req_extensions = v3_req                                      >>openssl.req.cnf
 echo distinguished_name = req_distinguished_name                  >>openssl.req.cnf

 echo [ req_distinguished_name ]                                   >>openssl.req.cnf

 echo [ v3_req ]                                                   >>openssl.req.cnf
 echo basicConstraints = CA:FALSE                                  >>openssl.req.cnf
 echo keyUsage = nonRepudiation, digitalSignature, keyEncipherment >>openssl.req.cnf

 openssl req -new -key gatewaykey.pem -days 1096 -batch  -utf8 -subj "/CN=127.0.0.1" -config openssl.req.cnf -out gateway.csr

 del openssl.req.cnf
)

rem // Если это не первое выполнение данного скрипта, то в index.txt может храниться индекс следующей DNS записи.

if exist "index.txt" (
 set /p index=<index.txt
)

if not exist "index.txt" (
 set index=2
)

rem // Мы создаём openssl.cnf один раз и в дальнейшем дополняем его новыми доменами.

if not exist "openssl.cnf" (

 echo basicConstraints = CA:FALSE   >openssl.cnf
 echo extendedKeyUsage = serverAuth >>openssl.cnf
 echo subjectAltName=@alt_names     >>openssl.cnf
 echo [alt_names]                   >>openssl.cnf
 echo IP.1 = 127.0.0.1              >>openssl.cnf 
 echo DNS.1 = localhost             >>openssl.cnf 

 set index=2
 del "index.txt"
)

rem // В цикле добавляем в openssl.cnf домены, которые заданы в командной строке либо будут введены пользователем.

:NEXT
set /a aindex=%index% + 1
set /a bindex=%index% + 2

set domain=%1

if !%domain% == ! (
 set /p domain=enter domain name or space:
)

if not !%domain% == ! (
 echo DNS.%index% = %domain%    >>openssl.cnf
 echo DNS.%aindex% = *.%domain% >>openssl.cnf

 echo %bindex% >index.txt

 set index=%bindex%
 shift
 goto NEXT
)

del gateway.pem

rem // Создаём сертификат IPFS шлюза 

openssl x509 -req -sha256 -days 1096 -in gateway.csr -CAkey rootkey.pem -CA rootcert.pem -set_serial %RANDOM%%RANDOM%%RANDOM%%RANDOM% -extfile openssl.cnf -out gateway.pem

rem // Записываем ключ и сертификат в stunnel.pem, который по умолчанию используется программой stunnel

copy /b gateway.pem+gatewaykey.pem stunnel.pem

rem // Даём пользователю прочитать ошибки или информацию

pause