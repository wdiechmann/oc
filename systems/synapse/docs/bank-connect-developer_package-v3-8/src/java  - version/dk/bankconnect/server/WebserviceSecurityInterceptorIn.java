package dk.bankconnect.server;

import java.io.IOException;
import java.io.InputStream;
import java.security.KeyStoreException;
import java.security.NoSuchAlgorithmException;
import java.security.UnrecoverableKeyException;
import java.security.cert.CertificateException;
import java.util.HashSet;
import java.util.Properties;
import java.util.Set;

import javax.annotation.Resource;
import javax.servlet.http.HttpServletRequest;
import javax.xml.namespace.QName;
import javax.xml.parsers.DocumentBuilderFactory;
import javax.xml.parsers.ParserConfigurationException;
import javax.xml.transform.TransformerConfigurationException;
import javax.xml.transform.TransformerException;
import javax.xml.ws.WebServiceContext;

import org.apache.commons.logging.Log;
import org.apache.commons.logging.LogFactory;
import org.apache.cxf.binding.soap.SoapMessage;
import org.apache.cxf.binding.soap.interceptor.AbstractSoapInterceptor;
import org.apache.cxf.helpers.XMLUtils;
import org.apache.cxf.interceptor.Fault;
import org.apache.cxf.phase.Phase;
import org.apache.ws.security.WSConstants;
import org.apache.ws.security.WSSecurityException;
import org.apache.ws.security.util.WSSecurityUtil;
import org.springframework.core.io.support.PropertiesLoaderUtils;
import org.w3c.dom.Document;
import org.w3c.dom.Element;
import org.xml.sax.SAXException;

import dk.bankconnect.BankConnectConstants;
import dk.bankconnect.certificate.CertificateService;
import dk.bankconnect.certificate.CertificateServiceImpl;
import dk.bankconnect.security.SecurityException;
import dk.bankconnect.security.SecurityService;
import dk.bankconnect.security.SecurityServiceImpl;
import dk.bankconnect.server.config.Constants;

/**
 * The WebserviceSecurityInterceptorIn class extends the AbstractSoapInterceptor
 * class.
 */
public class WebserviceSecurityInterceptorIn extends AbstractSoapInterceptor {
    private Log logger = LogFactory.getFactory().getInstance(WebserviceSecurityInterceptorIn.class);
    @Resource
    WebServiceContext webServiceContext;

    private static final Set<QName> HEADERS = new HashSet<QName>();
    static {
        HEADERS.add(new QName(WSConstants.WSSE_NS, WSConstants.WSSE_LN));
        HEADERS.add(new QName(WSConstants.WSSE11_NS, WSConstants.WSSE_LN));
        HEADERS.add(new QName(WSConstants.ENC_NS, WSConstants.ENC_DATA_LN));
    }

    @Override
    public Set<QName> getUnderstoodHeaders() {
        return HEADERS;
    }

    /**
     * Constructor.
     */
    public WebserviceSecurityInterceptorIn() {
        super(Phase.POST_STREAM);
    }

    /**
     * Handle soap message.
     * 
     * @param msg
     *            Soap message
     * @throws Fault
     * @see org.apache.cxf.interceptor.Fault
     * @throws SecurityException
     * @see SecurityException
     * @throws UnrecoverableKeyException
     * @see UnrecoverableKeyException
     * @throws KeyStoreException
     *             KeyStoreException
     * @throws NoSuchAlgorithmException
     * @see NoSuchAlgorithmException
     * @throws CertificateException
     *             CertificateException
     * @throws ParserConfigurationException
     *             ParserConfigurationException
     * @throws SAXException
     *             SAXException
     * @throws IOException
     * @see IOException
     * @throws WSSecurityException
     *             WSSecurityException
     * @throws TransformerConfigurationException
     *             TransformerConfigurationException
     * @throws TransformerException
     *             TransformerException
     * @throws Exception
     * @see Exception
     */
    @Override
    public void handleMessage(SoapMessage msg) throws Fault {
        logger.debug(this.getClass().getName() + " has been invoked");
        try {
            HttpServletRequest httpServletRequest = (HttpServletRequest) msg.get("HTTP.REQUEST");
            String queryString = httpServletRequest.getQueryString();
            if ((queryString != null) && (httpServletRequest.getQueryString().contains("wsdl"))) {
                return;
            }
            if (messageContainsWSSHeader(msg)) {
                InputStream inputStream = msg.getContent(InputStream.class);
                DocumentBuilderFactory documentBuilderFactory = DocumentBuilderFactory.newInstance();
                documentBuilderFactory.setNamespaceAware(true);
                Document secureDoc = documentBuilderFactory.newDocumentBuilder().parse(inputStream);

                SecurityService ssi = new SecurityServiceImpl();
                CertificateService csi = new CertificateServiceImpl();
                Properties properties = PropertiesLoaderUtils.loadAllProperties(Constants.PROPERTY_FILE);
                String privateKey = properties.getProperty("dk.bankconnect.security.bankconnectcrypto.private.key");

                Document unwrappedSOAPMessage = ssi.unwrapSOAPMessage(secureDoc,
                        csi.getKeyFromKeystore(null, privateKey).getEncoded());

                msg.setContent(InputStream.class, XMLUtils.getInputStream(unwrappedSOAPMessage));
            }
        } catch (SecurityException e) {
            throw e.getAsSoapFault();
        } catch (UnrecoverableKeyException e) {
            SecurityException sException = new SecurityException(e);
            sException.setErrorcode(BankConnectConstants.INVALID_DECRYPTION);
            throw sException.getAsSoapFault();
        } catch (KeyStoreException e) {
            SecurityException sException = new SecurityException(e);
            sException.setErrorcode(BankConnectConstants.INVALID_DECRYPTION);
            throw sException.getAsSoapFault();
        } catch (NoSuchAlgorithmException e) {
            SecurityException sException = new SecurityException(e);
            sException.setErrorcode(BankConnectConstants.INVALID_DECRYPTION);
            throw sException.getAsSoapFault();
        } catch (CertificateException e) {
            SecurityException sException = new SecurityException(e);
            sException.setErrorcode(BankConnectConstants.INVALID_CERTIFICATE);
            throw sException.getAsSoapFault();
        } catch (ParserConfigurationException e) {
            SecurityException sException = new SecurityException(e);
            sException.setErrorcode(BankConnectConstants.FORMAT_ERROR);
            throw sException.getAsSoapFault();
        } catch (SAXException e) {
            SecurityException sException = new SecurityException(e);
            sException.setErrorcode(BankConnectConstants.FORMAT_ERROR);
            throw sException.getAsSoapFault();
        } catch (IOException e) {
            SecurityException sException = new SecurityException(e);
            sException.setErrorcode(BankConnectConstants.FORMAT_ERROR);
            throw sException.getAsSoapFault();
        } catch (WSSecurityException e) {
            SecurityException sException = new SecurityException(e);
            sException.setErrorcode(BankConnectConstants.INVALID_SIGNATURE);
            throw sException.getAsSoapFault();
        } catch (TransformerConfigurationException e) {
            SecurityException sException = new SecurityException(e);
            sException.setErrorcode(BankConnectConstants.INVALID_SIGNATURE);
            throw sException.getAsSoapFault();
        } catch (TransformerException e) {
            SecurityException sException = new SecurityException(e);
            sException.setErrorcode(BankConnectConstants.FORMAT_ERROR);
            throw sException.getAsSoapFault();
        } catch (Exception e) {
            SecurityException sException = new SecurityException(e);
            throw sException.getAsSoapFault();
        }
    }

    /**
     * Determine if the soap message contains WS header.
     * 
     * @param msg
     *            Soap message
     * @return If true the message contains a WS header, otherwise false
     * @throws ParserConfigurationException
     *             ParserConfigurationException
     * @throws SAXException
     *             SAXException
     * @throws IOException
     * @see IOException
     * @throws WSSecurityException
     *             WSSecurityException
     * @throws SecurityException
     */
    private boolean messageContainsWSSHeader(SoapMessage msg) throws SecurityException {
        boolean foundWSSHeaders = false;
        try {
            Document doc = XMLUtils.parse(msg.getContent(InputStream.class));
            Element securityHeader = WSSecurityUtil.getSecurityHeader(doc, null);
            foundWSSHeaders = (securityHeader != null);
            if (PropertiesLoaderUtils.loadAllProperties(Constants.PROPERTY_FILE)
                    .getProperty("dk.bankconnect.server.force.wssecurity").equalsIgnoreCase("true")) {
                logger.info("Forecing security due to wsssecurity in " + Constants.PROPERTY_FILE);
                foundWSSHeaders = true;
            }

            msg.getExchange().put("bankconnect.security", new Boolean(foundWSSHeaders));
            msg.setContent(InputStream.class, XMLUtils.getInputStream(doc));
        } catch (Exception e) {
            SecurityException sException = new SecurityException(e);
            sException.setErrorcode(BankConnectConstants.FORMAT_ERROR);
            throw sException;
        }
        return foundWSSHeaders;
    }
}
