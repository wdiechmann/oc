package dk.bankconnect.server.config;

/**
 * Global constants for Bank Connect
 * 
 * @author Morten Sabroe Mortensen/BDYMMN
 */
public class Constants {
    public static final String MOCKSERVERPATH = "/mockserver/";
    public static final String WSSE_NS = "http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd";
    public  static final String WSU_NS = "http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-utility-1.0.xsd";
    public  static final String XMLDSIG_NS = "http://www.w3.org/2000/09/xmldsig#";
    
    public static final String CORPORATESERVICE_NAMESPACE = "http://bankconnect.dk/schema/2014";
    public static final String SOAP_NAMESPACE = "http://schemas.xmlsoap.org/soap/envelope/";
    public static final boolean validateContentByXMLSchema = true;
    public static final boolean validateContentByCGIRules = true;

    public static final boolean validateContentByXMLSchema_FailOnError = true;
    public static final boolean validateContentByCGIRules_FailOnError = true;

    public static final Long contentDecompressionLimit = 5L * 1024L * 1024L; // 5
                                                                             // MiB
    /** The Constant JCE_PROVIDER. */
    public static final String JCE_PROVIDER = "BC";
    /** The Constant KEY_ALGORITHM. */
    public static final String KEY_ALGORITHM = "RSA";
    
    public static final String PROPERTY_FILE="server.properties";
    public static final String PROP_VALIDATE_CERTIFICATE="dk.bankconnect.security.bankconnectcrypto.validatecertificate";
    public static final String PROP_CRYPTO_PROVIDER="org.apache.ws.security.crypto.provider";
    

}
