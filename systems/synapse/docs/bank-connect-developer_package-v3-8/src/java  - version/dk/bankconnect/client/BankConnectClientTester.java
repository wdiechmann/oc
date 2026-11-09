package dk.bankconnect.client;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileNotFoundException;
import java.io.FileWriter;
import java.io.IOException;
import java.io.InputStream;
import java.security.Key;
import java.security.KeyStoreException;
import java.security.NoSuchAlgorithmException;
import java.security.PrivateKey;
import java.security.UnrecoverableKeyException;
import java.security.cert.CertificateException;
import java.security.cert.X509Certificate;
import java.util.ArrayList;
import java.util.List;

import javax.xml.crypto.dsig.Reference;
import javax.xml.crypto.dsig.XMLSignature;
import javax.xml.crypto.dsig.XMLSignatureFactory;
import javax.xml.crypto.dsig.dom.DOMValidateContext;
import javax.xml.parsers.DocumentBuilder;
import javax.xml.parsers.DocumentBuilderFactory;
import javax.xml.parsers.ParserConfigurationException;
import javax.xml.transform.Source;
import javax.xml.transform.Transformer;
import javax.xml.transform.TransformerException;
import javax.xml.transform.TransformerFactory;
import javax.xml.transform.TransformerFactoryConfigurationError;
import javax.xml.transform.dom.DOMSource;
import javax.xml.transform.stream.StreamResult;

import org.apache.commons.codec.binary.Base64;
import org.apache.commons.logging.Log;
import org.apache.commons.logging.LogFactory;
import org.apache.ws.security.WSSecurityEngine;
import org.apache.ws.security.WSSecurityEngineResult;
import org.apache.ws.security.WSSecurityException;
import org.apache.ws.security.components.crypto.CryptoFactory;
import org.w3c.dom.DOMException;
import org.w3c.dom.Document;
import org.w3c.dom.Element;
import org.w3c.dom.NamedNodeMap;
import org.w3c.dom.Node;
import org.w3c.dom.NodeList;
import org.xml.sax.SAXException;

import dk.bankconnect.BankConnectXmlValidator;
import dk.bankconnect.certificate.CertificateService;
import dk.bankconnect.certificate.CertificateServiceImpl;
import dk.bankconnect.security.BankConnectCrypto;
import dk.bankconnect.security.SecurityException;
import dk.bankconnect.security.SecurityServiceImpl;
import dk.bankconnect.server.config.Constants;

public class BankConnectClientTester {

    private InputStream keystoreStream = null;

    private Log logger = LogFactory.getFactory().getInstance(BankConnectClientTester.class);

    private SecurityServiceImpl securityServiceImpl = new SecurityServiceImpl();
    private CertificateService certificateServiceImpl = new CertificateServiceImpl();

    /**
     * @param args
     */
    public static void main(String[] args) {

        setup(args);
        BankConnectClientTester bct = new BankConnectClientTester();
        try {
            System.out.println("Fecthing certificates and keys from: " + args[4]);
            InputStream keystoreStream = new FileInputStream(new File(args[4]));
            bct.setupKeystore(keystoreStream);
        } catch (Exception e) {
            System.out.println("No keystore parameter - defaulting to bankconnect.jks");
        }

        if ("unwrap".equalsIgnoreCase(args[0])) {
            bct.unwrap(args[1], args[2]);
        }
        if ("wrap".equalsIgnoreCase(args[0])) {
            bct.wrap(args[1], args[2], args[3]);
        }

        if ("verify".equalsIgnoreCase(args[0])) {
            bct.verify(args[1]);
        }

        if ("vws".equalsIgnoreCase(args[0])) {
            bct.validateWssSignature(args[1]);
        }

    }

    private void validateWssSignature(String filename) {
        logger.info("Processing file " + filename);
        DocumentBuilderFactory domFactory = DocumentBuilderFactory.newInstance();
        domFactory.setNamespaceAware(true);
        DocumentBuilder domBuilder;
        File file = new File(".");
        boolean coreValidity = true;
        String validationMessage = "The validation of the WSS signature is: ";
        try {

            logger.info("Parsing xml");
            domBuilder = domFactory.newDocumentBuilder();
            Document xmlDocument = domBuilder.parse(new FileInputStream(new File(filename)));
            logger.info("Getting signature");
            NodeList signaturList = xmlDocument.getElementsByTagNameNS(Constants.XMLDSIG_NS, "Signature");
            logger.info("Found no of signatures " + signaturList.getLength());
            if (signaturList.getLength() == 0) {
                logger.error("No signature found for validation");
            } else {
                logger.info("Getting certificate (KeyIdentifier)");
                NodeList certificateList = xmlDocument.getElementsByTagNameNS(Constants.WSSE_NS, "KeyIdentifier");
                logger.info("Found no of certificates " + certificateList.getLength());
                if (certificateList.getLength() == 0) {
                    logger.error("No certificate found !");
                } else {
                    Node certificateItem = certificateList.item(0);
                    CertificateServiceImpl csi = new CertificateServiceImpl();
                    List<X509Certificate> certificatesFromPEMString = csi.getCertificatesFromPEMString(certificateItem
                            .getTextContent());
                    X509Certificate certificate = certificatesFromPEMString.get(0);
                    logger.info("Found and using certificate " + certificate.getSubjectX500Principal());
                    Key validatingKey = certificate.getPublicKey();
                    XMLSignatureFactory factory = XMLSignatureFactory.getInstance("DOM");
                    for (int i = 0; (i < signaturList.getLength()) && coreValidity; i++) {
                        logger.info("Processing signature...");
                        Node signatureElement = signaturList.item(i);

                        DOMValidateContext headerContext = new DOMValidateContext((Key) validatingKey, signatureElement);
                        logger.info("DOMValidateContext created");
                        XMLSignature signature = factory.unmarshalXMLSignature(headerContext);
                        logger.info("Signature unmarshalled");
                        List<Reference> references = signature.getSignedInfo().getReferences();
                        for (Reference ref : references) {
                            logger.info("Dereferencing and adding id: " + ref.getURI());
                            Element elementWithId = getNodeWithAttribute(signatureElement.getOwnerDocument(), "Id", ref
                                    .getURI().replace("#", ""));
                            headerContext.setIdAttributeNS(elementWithId, Constants.WSU_NS, "Id");
                        }
                        coreValidity = signature.validate(headerContext);
                        logger.info("Signature " + signature.getId() + " has been found and validated: " + coreValidity);
                    }
                }
            }

            validationMessage += coreValidity;
            if (coreValidity != true)
                enchanceErrorMessageIfPossible(validationMessage, xmlDocument);

        } catch (Exception e) {
            logger.error("No valid SignedInfo or Reference found. ", e);
            coreValidity = false;
        }
        logger.info(validationMessage);

    }

    private void setupKeystore(InputStream jks) {
        keystoreStream = jks;
    }

    private void verify(String filename) {

        File file = new File(".");

        try {
            File xmlFile = new File(filename);
            BankConnectXmlValidator bcxv = new BankConnectXmlValidator();
            bcxv.validateSoapXml(new FileInputStream(xmlFile));
            logger.info("Schema verify is ok!");
        } catch (FileNotFoundException e) {
            logger.error("Current directory is : " + file.getAbsolutePath());
            logger.error(e);
        } catch (SAXException e) {
            logger.error(e);
        } catch (IOException e) {
            logger.error("Current directory is : " + file.getAbsolutePath());
            logger.error(e);
        }

    }

    private static void setup(String[] args) {
        if (args.length < 5) {
            System.out.println("A Bank Connect client utility.");
            System.out.println("Arguments:");
            System.out.println("1: command (unwrap|wrap|verify|vws)");
            System.out.println("2: inputfile");
            System.out.println("3: signing key/certificate alias");
            System.out.println("4: encryption certificate alias");
            System.out.println("5: keystore (if blank use bankconnect.jks)");
            System.out.println("");
            System.out
                    .println("exam: java -c BankConnectClientTester unwrap c:/files/server-soap-message.xml erp-xyz na na");
            System.out
                    .println("exam: java -c BankConnectClientTester wrap c:/files/client-soap-message.xml erp-xyz \"bank connect-test\" mykeystore.jks");
            System.out
                    .println("exam: java -c BankConnectClientTester verify c:/files/client-soap-message.xml na na na");
            System.out.println("exam: java -c BankConnectClientTester vws c:/files/client-soap-message.xml na na na");
            System.exit(-1);
        }
    }

    private void wrap(String filename, String signingAlias, String encryptionAlias) {
        DocumentBuilderFactory domFactory = DocumentBuilderFactory.newInstance();
        domFactory.setNamespaceAware(true);
        DocumentBuilder domBuilder;
        File file = new File(".");

        try {
            domBuilder = domFactory.newDocumentBuilder();
            Document xmlDocument = domBuilder.parse(new FileInputStream(new File(filename)));
            PrivateKey key = (PrivateKey) certificateServiceImpl.getKeyFromKeystore(keystoreStream, signingAlias);
            X509Certificate signCertificate = certificateServiceImpl.getCertificateFromKeystore(keystoreStream,
                    signingAlias);
            X509Certificate encCertificate = certificateServiceImpl.getCertificateFromKeystore(keystoreStream,
                    encryptionAlias);
            Document wrapSOAPMessage = securityServiceImpl.wrapSoapMessage(xmlDocument, signCertificate.getEncoded(),
                    key.getEncoded(), encCertificate.getEncoded());
            writeToFile(wrapSOAPMessage, filename);

        } catch (ParserConfigurationException e) {
            logger.error("Unable to process file: " + filename);
            logger.error("Current directory is : " + file.getAbsolutePath());
            logger.error(e);
        } catch (SAXException e) {
            logger.error(e);
        } catch (IOException e) {
            logger.error("Current directory is : " + file.getAbsolutePath());
            logger.error(e);
        } catch (IllegalArgumentException e) {
            logger.error("Current directory is : " + file.getAbsolutePath());
            logger.error(e);
        } catch (SecurityException e) {
            logger.error(e.getErrorcode());
            logger.error(e.getErrorMessage());
        } catch (UnrecoverableKeyException e) {
            logger.error(e);
        } catch (KeyStoreException e) {
            logger.error(e);
        } catch (NoSuchAlgorithmException e) {
            logger.error(e);
        } catch (CertificateException e) {
            logger.error(e);
        } catch (TransformerFactoryConfigurationError e) {
            logger.error(e);
        } catch (TransformerException e) {
            logger.error(e);
        }
    }

    private void writeToFile(Document soapMessage, String filename) throws IOException,
            TransformerFactoryConfigurationError, TransformerException {
        String property = System.getProperty("file.separator");
        int i = filename.lastIndexOf(property);
        if (i < 0) {
            i = 0;
        }
        String path = filename.substring(0, i++) + property;
        String fname = filename.substring(i, filename.length());
        filename = path + "processed-" + fname;
        logger.info("Writing file " + filename);
        DOMSource is = new DOMSource(soapMessage);
        FileWriter writer;

        writer = new FileWriter(filename);
        Transformer transformer = TransformerFactory.newInstance().newTransformer();
        transformer.transform((Source) is, new StreamResult(writer));

    }

    private void unwrapUsingOnlyWSS(String filename, String alias) {
        DocumentBuilderFactory domFactory = DocumentBuilderFactory.newInstance();
        domFactory.setNamespaceAware(true);
        DocumentBuilder domBuilder;
        File file = new File(".");
        Document xmlDocument = null;
        File xmlFile = new File(filename);
        try {
            domBuilder = domFactory.newDocumentBuilder();
            xmlDocument = domBuilder.parse(new FileInputStream(xmlFile));
            PrivateKey key = (PrivateKey) certificateServiceImpl.getKeyFromKeystore(keystoreStream, alias);
            logger.debug("Setting up security engine");
            PasswordCallback cb = new PasswordCallback();
            WSSecurityEngine secEngine = new WSSecurityEngine();

            BankConnectCrypto bankConnectCrypto = (BankConnectCrypto) CryptoFactory.getInstance(Constants.PROPERTY_FILE);

            bankConnectCrypto.setSingleCertificate(null);
            bankConnectCrypto.setSingleKey(key);
            List<WSSecurityEngineResult> results = secEngine.processSecurityHeader(xmlDocument, null, cb,
                    bankConnectCrypto, bankConnectCrypto);

        } catch (ParserConfigurationException e) {
            logger.error(e);
        } catch (FileNotFoundException e) {
            logger.error("Current directory is : " + file.getAbsolutePath());

            logger.error(e);
        } catch (SAXException e) {
            logger.error(e);
        } catch (IOException e) {
            logger.error("Current directory is : " + file.getAbsolutePath());
            logger.error(e);
        } catch (UnrecoverableKeyException e) {
            logger.error(e);
        } catch (KeyStoreException e) {
            logger.error(e);
        } catch (NoSuchAlgorithmException e) {
            logger.error(e);
        } catch (CertificateException e) {
            logger.error(e);
        } catch (WSSecurityException e) {
            logger.error(e);
        }
    }

    private void unwrap(String filename, String alias) {
        DocumentBuilderFactory domFactory = DocumentBuilderFactory.newInstance();
        domFactory.setNamespaceAware(true);
        DocumentBuilder domBuilder;
        File file = new File(".");
        Document xmlDocument = null;
        File xmlFile = new File(filename);
        try {
            domBuilder = domFactory.newDocumentBuilder();
            xmlDocument = domBuilder.parse(new FileInputStream(xmlFile));
            PrivateKey key = (PrivateKey) certificateServiceImpl.getKeyFromKeystore(keystoreStream, alias);
            Document unwrapSOAPMessage = securityServiceImpl.unwrapSOAPMessage(xmlDocument, key.getEncoded());

            writeToFile(unwrapSOAPMessage, filename);
        } catch (ParserConfigurationException e) {
            logger.error("Unable to process file: " + filename);
            logger.error("Current directory is : " + file.getAbsolutePath());
            logger.error(e);
        } catch (SAXException e) {
            logger.error(e);
        } catch (IOException e) {
            logger.error("Current directory is : " + file.getAbsolutePath());
            logger.error(e);
        } catch (IllegalArgumentException e) {
            logger.error("Current directory is : " + file.getAbsolutePath());
            logger.error(e);
        } catch (SecurityException e) {
            logger.error(e.getErrorcode());
            logger.error(e.getErrorMessage());
            enchanceErrorMessageIfPossible(e.getErrorMessage(), xmlDocument);
        } catch (UnrecoverableKeyException e) {
            logger.error(e);
        } catch (KeyStoreException e) {
            logger.error(e);
        } catch (NoSuchAlgorithmException e) {
            logger.error(e);
        } catch (CertificateException e) {
            logger.error(e);
        } catch (TransformerFactoryConfigurationError e) {
            logger.error(e);
        } catch (TransformerException e) {
            logger.error(e);
        } finally {
            if (xmlDocument != null) {
                extractCertificates(xmlDocument);
            }
        }
    }

    private void enchanceErrorMessageIfPossible(String errorMessage, Document xmlDocument) {
        if (errorMessage.contains("Cannot handle multiple data references")) {
            NodeList elemList = xmlDocument.getElementsByTagNameNS("local", "KeyName");
            if (elemList != null) {
                logger.error("KeyInfo must NOT contain KeyName");
            }
        }
        if (errorMessage.contains("The signature or decryption was invalid")) {
            logger.error("Check for the correct certificate");
        }

        if (errorMessage.contains("The signature or decryption was invalid")) {
            NodeList elementList = xmlDocument.getElementsByTagNameNS("*", "endToEndMessageId");
            if ((elementList != null) && (elementList.getLength() > 0)) {
                int size = elementList.item(0).getTextContent().length();
                if (size > 36) {
                    logger.error("endToEndMessageId is larger that 35 = " + size);
                }
            }
        }

        if (errorMessage.contains("The validation of the WSS signature")) {
            logger.error("The standard WSS signature has failed");
            logger.error("This is most likely a key issue. Verifiy that the signature has been made with the privatekey");
            logger.error("Verify it is the correct certificate used");
            logger.error("Verify the JDK and juristriction policy and try verifying with a newer JDK");
        }
    }

    private void extractCertificates(Document xmlDocument) {
        logger.info("Listing certificates from SOAP message...");
        List<X509Certificate> certificates = new ArrayList<X509Certificate>();
        try {
            NodeList nodeList = xmlDocument.getElementsByTagNameNS(Constants.WSSE_NS, "BinarySecurityToken");
            for (int i = 0; i < nodeList.getLength(); i++) {
                NamedNodeMap attributes = nodeList.item(i).getAttributes();
                if (attributes
                        .getNamedItem("ValueType")
                        .getTextContent()
                        .equalsIgnoreCase(
                                "http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-x509-token-profile-1.0#X509v3")) {
                    certificates.add(certificateServiceImpl.getCertificate(Base64.decodeBase64(nodeList.item(i)
                            .getTextContent())));
                }
            }
            nodeList = xmlDocument.getElementsByTagNameNS(Constants.WSSE_NS, "KeyIdentifier");
            for (int i = 0; i < nodeList.getLength(); i++) {
                NamedNodeMap attributes = nodeList.item(i).getAttributes();
                if (attributes
                        .getNamedItem("ValueType")
                        .getTextContent()
                        .equalsIgnoreCase(
                                "http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-x509-token-profile-1.0#X509v3")) {
                    certificates.add(certificateServiceImpl.getCertificate(Base64.decodeBase64(nodeList.item(i)
                            .getTextContent())));
                }
            }
            for (X509Certificate x509Certificate : certificates) {
                logger.info("Serialnumber: " + x509Certificate.getSerialNumber());
                logger.info("Subject: " + x509Certificate.getSubjectX500Principal());
            }
        } catch (CertificateException e) {
            logger.error(e);
        } catch (DOMException e) {
            logger.error(e);
        }

        /*
         * Map<String,String> nameSpaces=new HashMap<String, String>();
         * nameSpaces.put("soap","http://schemas.xmlsoap.org/soap/envelope/" );
         * XPath xPath= XPathFactory.newInstance().newXPath(); NamespaceContext
         * nc = new XPathNamespaceContext(nameSpaces);
         * xPath.setNamespaceContext(nc); String expression=
         * "/soap:Envelope/soap:Header[1]/*[namespace-uri()='http://bankconnect.dk/schema/2014' and local-name()='serviceHeader'][1]/@*[namespace-uri()='http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-utility-1.0.xsd' and local-name()='Id']"
         * ; try { String x=xPath.compile(expression).evaluate(xmlDocument);
         * 
         * } catch (XPathExpressionException e) { logger.error(e); }
         */

    }

    /**
     * Extracts the element matching the provided attribute name and value, from
     * the root node.
     * 
     * @param root
     *            The root node
     * @param attrName
     *            The attribute name
     * @param attrValue
     *            The attribute value
     * 
     * @return The extracted element
     */
    private Element getNodeWithAttribute(Node root, String attrName, String attrValue) {
        NodeList nl = root.getChildNodes();
        for (int i = 0; i < nl.getLength(); i++) {
            Node n = nl.item(i);
            if (n instanceof Element) {
                Element el = (Element) n;
                if (el.getAttributeNS(Constants.WSU_NS, attrName).equals(attrValue)) {
                    return el;
                } else {
                    el = getNodeWithAttribute(n, attrName, attrValue); // search
                                                                       // recursively
                    if (el != null) {
                        logger.debug("And got the corresponding xml element: " + el.getNodeName());
                        return el;
                    }
                }
            }
        }
        return null;
    }

}
