echo off
rem This file will generate the stub CS code used in the project.
rem If generation is successful, copy the file BankConnectService.cs into the SecuredClient project - replacing
rem the file already there.

rem Run this script in a Visual Studio developer console (to have disco and svcutil on path) after you have
rem altered the line below to refer the correct absolute location of the wsdl.

disco c:\Users\thomas\dev\bankconnectclient\svcutil\bankconnect.wsdl
svcutil *.wsdl *.xsd /out:BankConnectService.cs


