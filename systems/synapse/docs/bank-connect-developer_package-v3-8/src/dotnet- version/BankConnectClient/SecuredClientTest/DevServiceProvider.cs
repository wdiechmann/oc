using System;
using System.Security.Cryptography.X509Certificates;
using SecuredClient.Provider;

namespace SecuredClientTest
{
    public class DevServiceProvider : ServiceProvider
    {
        public override Uri Endpoint => new Uri("http://localhost:8080/bankconnect/services/CorporateService");
        public override string RegistrationNumber => "1234";

        public override X509Certificate2 RootCaCertificate
            => FromPemBlock("MIIFcTCCA1mgAwIBAgIBADANBgkqhkiG9w0BAQsFADBaMQswCQYDVQQGEwJESzEV" +
                            "MBMGA1UEChMMQmFuayBDb25uZWN0MRUwEwYDVQQLEwxCYW5rIENvbm5lY3QxHTAb" +
                            "BgNVBAMTFEJhbmsgQ29ubmVjdCBDQS10ZXN0MB4XDTE1MDQyOTE0MjgyM1oXDTQ1" +
                            "MDQyOTE0MjgyM1owWjELMAkGA1UEBhMCREsxFTATBgNVBAoTDEJhbmsgQ29ubmVj" +
                            "dDEVMBMGA1UECxMMQmFuayBDb25uZWN0MR0wGwYDVQQDExRCYW5rIENvbm5lY3Qg" +
                            "Q0EtdGVzdDCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBAIAyiSonn91u" +
                            "//67zAj+xBH9bQasJEvzqYW5e0Gl/aHyy0sWFA6vgu3hrqDBZX0KqgLn363U/Bgd" +
                            "LcY6hKIaiL13AY1A1oWaolViSKKIn0z4glRsbYw29BaJSWMjKLkkPAHZegwnKWOf" +
                            "v8ygxxVfUQ3Po22dk38IqCDkGNG4oNYKY9b1U7sweqSwRlRGY9mc7OPYlof7xL64" +
                            "XFtDeDqA77Vkee1s/5cE5r+hHPK4ei+TR149dzS3ifsuDfAOmuz+Bhtdh6rf+Zy8" +
                            "E3iy57P96JgQjQSYwj44sOaw6glWIzmuaGmxTcxznLOLa50mY7nLt9YqD3zvRRVQ" +
                            "FVCQWFD0NpHviy+uAeGMWLjFom37CS/gAKyNtp0lOoPgkqV09SwiYU1JHnfAcrB2" +
                            "b1RFjRyz207QCcXzqR02rVsdtkOtZW1wyIoecNk4ynG6xVyHQfAojhgzQ0cDHTaf" +
                            "VFSd9k5lVSnUfmkqX5bk3EvEEXQPl9naywrOQW7VAbMnDSTQZevXdoudXgmNd867" +
                            "kilKdioCsLrsNH4o4y2G1S3LnuXT1VO7nWTL5k8Rnyt2mA6D8w/HDksd4r+FDKc/" +
                            "2nBK3eiQvOUgkxNawYlvc+vq0gnfjj3jlwHQxQ4dbmx4Kx07BKoZ1uzrHxNR8I8p" +
                            "Mzx/5WXqyhwb6l0PCl5oCh7h0voL6ZsJAgMBAAGjQjBAMB0GA1UdDgQWBBRhM9j4" +
                            "L1srfG/D/7q1Ytflb2UsXTAPBgNVHRMBAf8EBTADAQH/MA4GA1UdDwEB/wQEAwIC" +
                            "BDANBgkqhkiG9w0BAQsFAAOCAgEALKOcdEzEBPgHOhl3Iew47ldBrs0JfPoL0C0D" +
                            "gqWbMzhMPlthUD2j3DlyHOT188lm7uCbgiC18byM6qeyiGcxK+jKVOKxkbPSL5Tt" +
                            "nAc+XQ76xzMaZzSvOuFLH29DMQt9dkF3xHrd4NZoYPu5OOpsylJpohmP3OfyuQ+u" +
                            "4cu89tvT73eVgXdZ60mfc3wsXGhf4rV9FjyMDv0FpzEevu7/65rEa3/7Sgng6Lpo" +
                            "Xfl+xBguKz4GqiUUdf8B2PAITecRb52emjwZyCgwLOBJWZaKmKeHxKpYhC+Oir+m" +
                            "e3ucO8XQa79J4kpzsfm6uPeJwdtqlXSHpX5RlpjRhColRHbA7r6r2usV3fIVDKSU" +
                            "dKMyiq0pv4TL2Hf495B8H0xZ4R+6NtZtBFan0787CapsJLvdVGq+lJnsij+ipfgp" +
                            "K3JmBaUXcyl4pVZMAdP1V28UuOKB5HcIU6sCD8xc4pVNJWm48eojpZoCwJcpHYAj" +
                            "tJ4DTIvDxMxUaEaRZR1Ju2veoULMk5ukw3ALnRHsD6lth2LkZPdoINS0TimUQQaF" +
                            "1Sqh4njZO5LTtmt3MkxyQQpvC9qrDp6znJJRm1tMGVLDjFPuaIqIW0+gGaZmVUBY" +
                            "GiVcN2/f98WQ0UA+eukS3125WxdPZE2a30MHHwLO6QDxsk6NwAA0VPaNLacNAFE2" +
                            "uqDE0vQ=");

        public X509Certificate2 BankCertificate => new X509Certificate2(
            Convert.FromBase64String(
                "MIIDODCCAiCgAwIBAgIGAU0FlCVCMA0GCSqGSIb3DQEBCwUAMFoxCzAJBgNVBAYT" +
                "AkRLMRUwEwYDVQQKEwxCYW5rIENvbm5lY3QxFTATBgNVBAsTDEJhbmsgQ29ubmVj" +
                "dDEdMBsGA1UEAxMUQmFuayBDb25uZWN0IElBLXRlc3QwHhcNMTUwNDI5MTQyODI0" +
                "WhcNMTgwNDI5MTQyODI0WjAcMRowGAYDVQQDExFiYW5rIGNvbm5lY3QtdGVzdDCC" +
                "ASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAI23KdtaRKPTFTe/A1PnsF9d" +
                "pSlTiXurKmio0OCgTP9wClHwync3JsInRwGTooA20P9zWobUnEFbEiAgRVYCxuYo" +
                "ldRE6NLhSC854/YTjMBeevH1TNa38lpavGiI4UwFhg70U9/JuYs21hoFyzVfaWlV" +
                "fOkAMm1U/n4wHq6FZW461S5PY4A/UI1Mr8WgeIHU9GqMBtFvjynzq3SLenOPgdmK" +
                "tyJ3V8EOU+DlgwKmDbxMVMtYNDZtoQvOWnuvlJ6ICDcqcW7OUkmwCKodjxxPvrda" +
                "PxyZDhT7h4FgRtrAOS8qR6L7x9D4ZIoxOMPudGvr99OSb4KVtaAEt/R7hKxG3OsC" +
                "AwEAAaNCMEAwHwYDVR0jBBgwFoAU680YSkZnx1IaJAmI49LlTGiia0wwHQYDVR0O" +
                "BBYEFMaWOY7Vf/iB3WVA96j5kRtbF8prMA0GCSqGSIb3DQEBCwUAA4IBAQAJ+bss" +
                "SFWE6KsYT7HSDKag4Eot7yNGMY4Don/MilDnOREdu20QUS131DKrSkpBQiCXbyRU" +
                "QjUoun4yue0EG+rlG3QUIlNNdJ4KZJB+dTYdLUV7XTYJNPimKAmoZ+PFNvT1eGgW" +
                "cMT+MbTfpk0mw0V8IprYGa8UPchd6vtSVwpbTcPc/F4bgUTlm/V+FG4bQS61gF0k" +
                "oj0DEZjzat7CBHpozRgfRlXgwu26vnhWGc99uKH4GAKN4JpqPi/6Yz+7iQNJUC3y" +
                "eezgBxFrIXuLpkBZSP4zunf9VxsICnxkFUXOTuYBdcbhPNzqMknD5ijFcFRZITwd" +
                "v7x3uJGLkM7iUfBp"));

        public X509Certificate2 IntermediateCertificate
            => FromPemBlock("MIIElzCCAn+gAwIBAgIGAU0FlCE6MA0GCSqGSIb3DQEBCwUAMFoxCzAJBgNVBAYT" +
                            "AkRLMRUwEwYDVQQKEwxCYW5rIENvbm5lY3QxFTATBgNVBAsTDEJhbmsgQ29ubmVj" +
                            "dDEdMBsGA1UEAxMUQmFuayBDb25uZWN0IENBLXRlc3QwHhcNMTUwNDI5MTQyODIz" +
                            "WhcNMjUwNDI5MTQyODIzWjBaMQswCQYDVQQGEwJESzEVMBMGA1UEChMMQmFuayBD" +
                            "b25uZWN0MRUwEwYDVQQLEwxCYW5rIENvbm5lY3QxHTAbBgNVBAMTFEJhbmsgQ29u" +
                            "bmVjdCBJQS10ZXN0MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAgBJq" +
                            "203+SB+9sk64SYrTsl/pj/54J4GyWJBmT9Z9CaR91CCSXrj0P1YnVrH3ZdkhlY3w" +
                            "9+qZfT/K5HAamT9C8ciuJrtFPxb4kxAthzJRCDXUu/6e1fhuVuIoRsnUm9OHZ83T" +
                            "Y1z07jzU8G3Ja29tKl5McrA/hSZB8bWxtzMk2gxOxq2loB1S7qMB26NqePuoI7SB" +
                            "w7NWBgijiCINRAps96oSg8UisQJtikOV5/I0n8zKcLWimmVh7J6ZVFDSG75l6OL7" +
                            "eQN0aqE7grEH1VQkio1GPI6Abz1bZqzIro3gubkr0ksVnbSzpnVsjtsT7Fp5w7Tn" +
                            "SfP0qkOWU8ocF3xakQIDAQABo2MwYTAfBgNVHSMEGDAWgBRhM9j4L1srfG/D/7q1" +
                            "Ytflb2UsXTAPBgNVHRMBAf8EBTADAQH/MB0GA1UdDgQWBBTrzRhKRmfHUhokCYjj" +
                            "0uVMaKJrTDAOBgNVHQ8BAf8EBAMCAoQwDQYJKoZIhvcNAQELBQADggIBABIZY8zf" +
                            "R5S65GkYFHI1VJ8J7L8k8vVLO9GOqOotsJdYBbJuv+DypODXkzb1TJR3j3b7TROC" +
                            "uuv+jo16yOGuMT5laiQdrkqNMHiBYwbpQFwiiOm9an5heyRMzYHEYrTw/VIRDnTb" +
                            "qDuUlQvPxrWgg8Vz2zFH5+OK/ywLFFAxpn1U40zBn9L9diaHUskSSjVlPqKHCT5C" +
                            "bOZioCgO2oBQes+VwCBc80B7uwYSp2SkSYrnXxH4HS/8KWjpGRBR7XU943bEAsxe" +
                            "unyrEXKmohOug06RtceHqZhRdmtAbVcwFl9qVNxT526lgM+M0/SEZxe7k3kEuYUx" +
                            "iOMNQKNp156ZE5UlwWellvopiJeZp/HOoxmyb4Vx9Ob7leRFOvT09QScdv3IugTN" +
                            "opzmcIfnjWkpUD9Tta29kS9/V8GBO9ZfkdRanFN81oqLvKuWGn47OZXmhMc7AlWy" +
                            "3gqETh8yzXjA4lcP9hDW1o6vkhr3GMJzVABf3BiMUNkdZdS+Vrc003X/571K+6Np" +
                            "8CKQwr9CCnmv445kfoVnY9dnhCXByBGZ+GDKWAMRAS3RRcMcd9A7twNFnGcGFGfm" +
                            "6HTX+OVJQLC3y2DZRUNher96EbeSxsi311oI6eVsobmCmquy3ngXjCL/Qc3brCDp" +
                            "5XwjoJVilBRQFwBoVSNR6oCvzuG6DJeiCFTw");

        public X509Certificate2 ClientCertificate => new X509Certificate2("erp.p12", "bankconnect", X509KeyStorageFlags.Exportable);
    }
}