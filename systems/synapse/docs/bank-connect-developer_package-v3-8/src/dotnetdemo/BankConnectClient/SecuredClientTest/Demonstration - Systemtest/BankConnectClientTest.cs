using System;
using System.IO;
using System.Xml;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using SecuredClient.Client;
using SecuredClient.Provider;
using SecuredClient.XmlSecurity;

namespace SecuredClientTest.Demonstration
{
    [TestClass]
    public class BankConnectClientTest
    {
        private BankConnectClient client;

        [TestMethod]
        [DeploymentItem("Resources/transferpayment-content-example.xml")]
        public void TestTransferPayment()
        {
            SetupClient();
            var xml = new XmlDocument();
            xml.Load("transferpayment-content-example.xml");
            var response = client.TransferPayment(XmlUtil.AsText(xml));
            Console.WriteLine(response.responseCode);
            Console.WriteLine(response.message);
            Console.WriteLine(response.endToEndMessageId);
        }

        private void SetupClient()
        {
            client = new BankConnectClient(
                new BankdataSystemtestServiceProvider(), 
                "0010444421001", 
                new FileInfo(@"C:\BCAHUB\cert\bankdata-stest.p12"), 
                "Test1234");
        }

        [TestMethod]
        public void TestGetStatus()
        {
            SetupClient();
            var status = client.GetStatus();
            Console.WriteLine(status.corporateMessage.compressed);
            var contentXml = new XmlDocument();
            contentXml.Load(new MemoryStream(status.corporateMessage.content));
            Console.WriteLine(XmlUtil.PrettyXml(contentXml));
        }

        [TestMethod]
        public void TestGetCustomerStatement()
        {
            SetupClient();
            var statement = client.GetCustomerStatement();
            Console.WriteLine(statement.corporateMessage.content.Length);
        }

        [TestMethod]
        public void TestGetCustomerAccountReport()
        {
            SetupClient();
            var report = client.GetCustomerAccountReport();
            Console.WriteLine(report.corporateMessage.content.Length);
        }

        [TestMethod]
        public void TestGetAlternate()
        {
            SetupClient();
            var alternate = client.GetAlternate();
            Console.WriteLine(alternate.corporateMessage.content.Length);
        }

        [TestMethod]
        public void TestGetDebitCreditNotification()
        {
            SetupClient();
            var notification = client.GetDebitCreditNotification();
            Console.WriteLine(notification.corporateMessage.content.Length);
        }
    }
}
