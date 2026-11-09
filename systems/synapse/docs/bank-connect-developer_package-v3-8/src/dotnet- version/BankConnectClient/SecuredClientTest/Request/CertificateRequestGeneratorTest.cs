using System;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using SecuredClient.Request;

namespace SecuredClientTest.Request
{
    [TestClass]
    public class CertificateRequestGeneratorTest
    {
        [TestMethod]
        public void Test()
        {
            var generator = new CertificateRequestGenerator("fid", "7368-2672-4205-1157");
            var pkcs10Bytes = generator.GetPkcs10Bytes();
            Assert.IsTrue(pkcs10Bytes.Length > 0);
        }
    }
}
