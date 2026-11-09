package dk.bankconnect;

public class BankConnectConstants {
    /**
     * The HTTP status code for OK.
     */
    public static final int OK = 200;
    /**
     * The HTTP status code for NO RESPONSE.
     */
    public static final int NO_CONTENT = 204;
    /**
     * The HTTP status code for BAD REQUEST.
     */
    public static final int BAD_REQUEST = 400;
    /**
     * The HTTP status code for BAD REQUEST.
     */
    public static final int MESSAGE_TO_LARGE = 413;
    /**
     * The HTTP status code for REQUEST ENTITY TOO LARGE.
     */
    public static final int SERVICE_UPGRADE = 426;
    /**
     * The HTTP status code for INTERNAL SERVER ERROR.
     */
    public static final int INTERNAL_SERVER = 500;
    /**
     * The HTTP status code for NOT IMPLEMENTED.
     */
    public static final int INVOKE_ERROR = 501;
    /**
     * The HTTP status code for GATEWAY TIMEOUT.
     */
    public static final int TIME_OUT = 504;
    /**
     * The HTTP status code for INVALID SIGNATURE.
     */
    public static final int INVALID_SIGNATURE = 631;
    /**
     * The HTTP status code for INVALID DECRYPTION.
     */
    public static final int INVALID_DECRYPTION = 633;
    /**
     * The HTTP status code for INVALID CERTIFICATE.
     */
    public static final int INVALID_CERTIFICATE = 634;
    /**
     * The status code for identification error exam activationcode.
     */
    public static final int IDENTIFICATION_ERROR = 701;
    /**
     * The HTTP status code for VALIDATION ERROR.
     */
    public static final int VALIDATION_ERROR = 710;
    /**
     * The HTTP status code for FORMAT ERROR.
     */
    public static final int FORMAT_ERROR = 711;
    /**
     * The HTTP status code for DECOMPRESSION ERROR.
     */
    public static final int DECOMPRESSION_ERROR = 712;
    /**
     * Defines the resource bundle.
     */
    public static final String RESOURCE_BUNDLE = "bankconnect";
    /**
     * Loglevel can be set to info or debug. When debug is set - exceptions are available in SOAP faults as detail.  
     */
    public static final String LOG_LEVEL = "loglevel";
}
