package dk.bankconnect;

import java.io.File;
import java.io.IOException;
import java.io.InputStream;

import javax.xml.XMLConstants;
import javax.xml.transform.Source;
import javax.xml.transform.stream.StreamSource;
import javax.xml.validation.Schema;
import javax.xml.validation.SchemaFactory;
import javax.xml.validation.Validator;

import org.apache.cxf.helpers.XMLUtils;
import org.w3c.dom.Document;
import org.xml.sax.SAXException;

public class BankConnectXmlValidator {

    public void validateSoapXml(Document xmlDoc) throws SAXException, IOException {
        try {
            validateSoapXml(XMLUtils.getInputStream(xmlDoc));
        } catch (Exception e) {
         throw new SAXException(e.getMessage());
        }
    }

    public void validateSoapXml(InputStream xmlDocStream) throws SAXException, IOException {
        SchemaFactory sf = SchemaFactory.newInstance(XMLConstants.W3C_XML_SCHEMA_NS_URI);

        Source[] xsdFiles = new StreamSource[4];
        xsdFiles[0] = new StreamSource(new File("resources/wsdl/xsd/bankconnect.xsd"));
        xsdFiles[1] = new StreamSource(new File("resources/wsdl/xsd/soap11.xsd"));
        xsdFiles[2] = new StreamSource(new File("resources/wsdl/xsd/xmldsig-core-schema.xsd"));
        xsdFiles[3] = new StreamSource(new File("resources/wsdl/xsd/exc-c14n.xsd"));

        Schema schema = sf.newSchema(xsdFiles);

        Validator validator = schema.newValidator();
        validator.validate(new StreamSource(xmlDocStream));
    }

}
