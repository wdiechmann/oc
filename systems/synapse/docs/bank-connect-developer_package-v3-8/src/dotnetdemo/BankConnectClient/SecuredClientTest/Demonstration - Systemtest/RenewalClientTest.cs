using System.IO;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using SecuredClient.Client;
using SecuredClient.Provider;

namespace SecuredClientTest.Demonstration
{
    [TestClass]
    public class RenewalClientTest
    {
        private RenewalClient client;

        [TestMethod]
        public void TestRenewal()
        {
            SetupClient();

            client.RenewCustomerCertificate(new FileInfo(@"C:\BCAHUB\cert\bankdata-stest-new.p12"), "Test1234");
        }

        private void SetupClient()
        {
            //Make sure test doesn't fail because of old data
            File.Delete(@"C:\BCAHUB\cert\bankdata-stest-new.p12"); 

            client = new RenewalClient(
                new BankdataSystemtestServiceProvider(),
                "0010444421001",
                new FileInfo(@"C:\BCAHUB\cert\bankdata-stest.p12"),
                "Test1234");
        }

    }
}
