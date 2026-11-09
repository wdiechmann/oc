using System.IO;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using SecuredClient.Client;
using SecuredClient.Provider;

namespace SecuredClientTest.Demonstration
{
    [TestClass]
    public class ActivationClientTest
    {
        private ActivationClient activationClient;

        //This test will only execute successfully once pr activation key.
        //We recommend setting it to [Ignore] after first successful activation.
        [Ignore]
        [TestMethod]
        public void TestActivation()
        {
            activationClient = new ActivationClient(
                new BankdataSystemtestServiceProvider(),
                "0010444421001", //Function identifier
                new FileInfo(@"C:\BCAHUB\cert\bankdata-stest.p12"),
                "Test1234"
                );
            activationClient.ActivateServiceAgreement("3651247851658423");
        }
    }
}