package dk.bankconnect.security;

import java.util.MissingResourceException;
import java.util.ResourceBundle;
import java.util.UUID;

import javax.xml.bind.annotation.XmlAccessType;
import javax.xml.bind.annotation.XmlAccessorType;
import javax.xml.bind.annotation.XmlRootElement;
import javax.xml.ws.WebFault;

import org.apache.commons.lang.exception.ExceptionUtils;
import org.apache.commons.logging.Log;
import org.apache.commons.logging.LogFactory;
import org.apache.cxf.binding.soap.SoapFault;
import org.apache.cxf.helpers.DOMUtils;
import org.w3c.dom.Element;

import dk.bankconnect.BankConnectConstants;

/**
 * Exception for holding security related exceptions
 * 
 * @author bdyaag
 * 
 */
@WebFault
@XmlAccessorType(XmlAccessType.FIELD)
@XmlRootElement
public class SecurityException extends Exception {
    private Log logger = LogFactory.getFactory().getInstance(SecurityException.class);

    private static final String DEFAULT_ERRORCODE = "500";

    private static final long serialVersionUID = 5750067848577841811L;

    private String errorcode;
    private String errorMessage;
    private String correlationId;
    private Exception exception;

    /**
     * Default constructor
     * 
     */
    public SecurityException() {
        this.setErrorcode(DEFAULT_ERRORCODE);
    }

    /**
     * Constructor for extracting basic message
     * 
     * @param exception
     *            The exception
     */
    public SecurityException(Exception exception) {
        this.exception = exception;
        errorcode = DEFAULT_ERRORCODE;
    }

    /**
     * Constructor for setting the basic message
     * 
     * @param message
     *            The message
     */
    public SecurityException(String message) {
        setMessage(message);
        errorcode = DEFAULT_ERRORCODE;
    }

    /**
     * Get the error code.
     * 
     * @return The error code
     */
    public String getErrorcode() {
        return errorcode;
    }

    /**
     * Set the error code and the corresponding error message from the properties.
     * 
     * @param errorcode
     *            The error code
     * @throws IllegalArgumentException
     *              If the errorcode is null or isn't defined in BankConnectConstants and properties file 
     */
    public void setErrorcode(String errorcode) throws IllegalArgumentException {
        if(errorcode != null){
            String resourceString = null;
            try {
                logger.debug("Looking up errorcode " + errorcode + " in resourcebundle "+ BankConnectConstants.RESOURCE_BUNDLE);
                resourceString = ResourceBundle.getBundle(BankConnectConstants.RESOURCE_BUNDLE).getString(errorcode);
                logger.debug("Setting errormessage to " + resourceString);
                errorMessage = resourceString;
                this.errorcode = errorcode;
            } catch (MissingResourceException e) {
                logger.error("Key not found in resourcebundle " + errorcode);
                throw new IllegalArgumentException("Illegal Errorcode");
            }
        }
        else{
            throw new IllegalArgumentException("Errorcode cannot be null");
        }
    }

    /**
     * Set the error code and the corresponding error message from the properties.
     * 
     * @param errorcode
     *            The error code
     * @throws IllegalArgumentException
     *              If the errorcode is null or isn't defined in BankConnectConstants and properties file 
     */
    public void setErrorcode(int errorcode) throws IllegalArgumentException {
        this.setErrorcode(String.valueOf(errorcode));
    }

    /**
     * Get the error message in the right format.
     * 
     * @return The error message
     */
    public String getErrorMessage() {
        if (errorMessage == null) {
            errorMessage = getErrorcode() + "#" + getCorrelationId() + "#" + errorMessage;
        }
        return errorMessage;
    }

    public String getCorrelationId() {
        if (correlationId == null) {
            correlationId = UUID.randomUUID().toString();
        }
        return correlationId;
    }

    public void setCorrelationId(String uuid) {
        correlationId = uuid;
    }

    /**
     * Set the error message
     * 
     * @param message
     *            The error message
     * @deprecated
     *          The appropriate error message will be found from the errorcode 
     */
    public void setMessage(String message) throws IllegalStateException{
        errorMessage = message;
    }

    public SoapFault getAsSoapFault() {
        SoapFault sf = new SoapFault(getErrorMessage(), SoapFault.FAULT_CODE_SERVER);
        if ("debug".equalsIgnoreCase(ResourceBundle.getBundle(BankConnectConstants.RESOURCE_BUNDLE).getString(
                BankConnectConstants.LOG_LEVEL))) {
            String trace = ExceptionUtils.getStackTrace(exception);
            logger.error(trace);
            Element element = DOMUtils.createDocument().createElement("exception");
            element.setTextContent(trace);
            sf.setDetail(element);
        }

        logger.error(sf);

        return sf;
    }

    @Override
    public String toString() {
        return "SecurityException [errorcode=" + errorcode + ", errorMessage=" + errorMessage + ", correlationId="
                + correlationId + ", exception=" + exception + "]";
    }
}
