using System.IO;
using System.ServiceModel.Channels;
using System.Text;
using System.Xml;

namespace SecuredClient.MessageSecurity
{
    public class MessageTransformer
    {
        private readonly Message originalMessage;

        public MessageTransformer(Message originalMessage)
        {
            this.originalMessage = originalMessage;
        }

        public XmlDocument GetXmlDocument()
        {
            var xmlWriterSetting = new XmlWriterSettings { Encoding = Encoding.UTF8 };
            var ms = new MemoryStream();
            var xmlWriter = XmlWriter.Create(ms, xmlWriterSetting);

            var msgbuf = originalMessage.CreateBufferedCopy(int.MaxValue);
            msgbuf.CreateMessage().WriteMessage(xmlWriter);

            xmlWriter.Flush();
            ms.Flush();
            ms.Position = 0;

            var xml = new XmlDocument { PreserveWhitespace = true, XmlResolver = null };
            xml.Load(ms);
            var doc = xml;
            return doc;
        }

        public Message ToMessage(XmlNode doc)
        {
            var memoryStream = new MemoryStream();
            var xmlWriter = XmlWriter.Create(memoryStream);

            doc.WriteTo(xmlWriter);
            xmlWriter.Flush();
            xmlWriter.Close();

            memoryStream.Position = 0;
            var dictionaryReader = XmlDictionaryReader.CreateTextReader(memoryStream, new XmlDictionaryReaderQuotas());
            return Message.CreateMessage(dictionaryReader, int.MaxValue, originalMessage.Version);
        }

    }
}
