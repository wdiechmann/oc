package dk.bankconnect.client;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.security.Key;

import javax.xml.parsers.DocumentBuilderFactory;
import javax.xml.parsers.ParserConfigurationException;
import javax.xml.transform.Transformer;
import javax.xml.transform.TransformerConfigurationException;
import javax.xml.transform.TransformerException;
import javax.xml.transform.TransformerFactory;
import javax.xml.transform.dom.DOMSource;
import javax.xml.transform.stream.StreamResult;

import org.apache.commons.logging.Log;
import org.apache.commons.logging.LogFactory;
import org.apache.cxf.binding.soap.SoapMessage;
import org.apache.cxf.binding.soap.interceptor.AbstractSoapInterceptor;
import org.apache.cxf.interceptor.Fault;
import org.apache.cxf.message.Message;
import org.apache.cxf.phase.Phase;
import org.w3c.dom.Document;
import org.xml.sax.SAXException;

import dk.bankconnect.security.SecurityService;
import dk.bankconnect.security.SecurityServiceImpl;

/**
 * The ClientSecurityInterceptorIn class.
 * <p>
 * The ClientSecurityInterceptorIn class extends from AbstractSoapInterceptor
 * class.
 */
public class ClientSecurityInterceptorIn extends AbstractSoapInterceptor {
    private Log logger = LogFactory.getFactory().getInstance(ClientSecurityInterceptorIn.class);
    private byte[] privateKey;

    /**
     * Constructor.
     */
    public ClientSecurityInterceptorIn() {
        super(Phase.POST_STREAM);
    }

    /**
     * Handle soap message.
     * <p>
     * Validates the soap message. If the soap message isn't valid an exception
     * is thrown.
     * 
     * @param msg
     *            the Soap Message
     * @throws SecurityException
     *             @see SecurityException
     * @throws TransformerConfigurationException
     *             TransformerConfigurationException
     * @throws TransformerException
     *             TransformerException
     * @throws IOException
     *             I/O exception
     * @throws SAXException
     *             SAXException
     * @throws ParserConfigurationException
     *             ParserConfigurationException
     */
    @Override
    public void handleMessage(SoapMessage msg) throws Fault {
        logger.debug(this.getClass().getName() + " has been invoked");
        if (msg.getExchange().getInMessage() != null) {
            try {
                setupMessageSecurity(msg);
                if (privateKey != null) {
                    InputStream inputStream = msg.getContent(InputStream.class);
                    DocumentBuilderFactory documentBuilderFactory = DocumentBuilderFactory.newInstance();
                    documentBuilderFactory.setNamespaceAware(true);
                    Document secureDoc = documentBuilderFactory.newDocumentBuilder().parse(inputStream);
                    try {
                        SecurityService ssi = new SecurityServiceImpl();
                        Document unwrappedSOAPMessage = ssi.unwrapSOAPMessage(secureDoc, privateKey);
                        TransformerFactory tf = TransformerFactory.newInstance();
                        Transformer trans = tf.newTransformer();
                        ByteArrayOutputStream bos = new ByteArrayOutputStream();
                        trans.transform(new DOMSource(secureDoc), new StreamResult(bos));
                        inputStream = new ByteArrayInputStream(bos.toByteArray());
                        msg.setContent(InputStream.class, inputStream);
                    } catch (dk.bankconnect.security.SecurityException e) {
                        throw e.getAsSoapFault();
                    } catch (Exception e) {
                        dk.bankconnect.security.SecurityException se = new dk.bankconnect.security.SecurityException(e);
                        throw se.getAsSoapFault();
                    }
                } else {
                    logger.debug("No privateKey applied - unwrapped bypassed");
                }
            } catch (Exception e) {
                dk.bankconnect.security.SecurityException se = new dk.bankconnect.security.SecurityException(e);
                throw se.getAsSoapFault();
            }
        }
    }

    /**
     * Setup security on soap message.
     * 
     * @param message
     *            the soap message
     */
    private void setupMessageSecurity(Message message) {
        Key privateKey = (Key) message.getExchange().get("dk.bankconnect.security.bankconnectcrypto.private.key");
        if (privateKey != null) {
            this.privateKey = privateKey.getEncoded();
        }
    }
}
