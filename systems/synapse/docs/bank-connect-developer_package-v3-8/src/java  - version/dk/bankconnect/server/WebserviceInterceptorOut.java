    package dk.bankconnect.server;

import java.util.Date;
import javax.xml.bind.JAXBException;
import javax.xml.datatype.DatatypeConfigurationException;
import javax.xml.datatype.DatatypeFactory;
import javax.xml.namespace.QName;

import org.apache.commons.logging.Log;
import org.apache.commons.logging.LogFactory;
import org.apache.cxf.binding.soap.SoapMessage;
import org.apache.cxf.binding.soap.interceptor.AbstractSoapInterceptor;
import org.apache.cxf.frontend.WSDLGetUtils;
import org.apache.cxf.headers.Header;
import org.apache.cxf.interceptor.Fault;
import org.apache.cxf.jaxb.JAXBDataBinding;
import org.apache.cxf.phase.Phase;
import org.joda.time.DateTime;

import dk.bankconnect.schema._2014.Duration;
import dk.bankconnect.schema._2014.ObjectFactory;
import dk.bankconnect.schema._2014.ServiceHeader;
import dk.bankconnect.schema._2014.TechnicalAddress;
import dk.bankconnect.server.config.Constants;

/**
 * The WebserviceInterceptorOut class extends  
 * the AbstractSoapInterceptor class.
 */
public class WebserviceInterceptorOut extends AbstractSoapInterceptor {
    private Log logger = LogFactory.getFactory().getInstance(WebserviceInterceptorOut.class);

    /**
     * Constructor.
     */
    public WebserviceInterceptorOut() {
        super(Phase.POST_LOGICAL);
    }

    /**
     * Handle soap message.
     * 
     * @param msg Soap message
     * @throws Fault @see org.apache.cxf.interceptor.Fault
     */
    @Override
    public void handleMessage(SoapMessage msg) throws Fault {
        logger.debug(this.getClass().getName() + " has been invoked");
/*        try {
            addheader(msg);
        } catch (DatatypeConfigurationException e) {
            logger.error(e);
            SoapFault sf = new SoapFault(e.getMessage(), SoapFault.FAULT_CODE_SERVER);
            throw sf;

        }*/
        // TODO: set soapaction
        
        Duration d = (Duration) msg.getExchange().get("duration");
        logger.debug(d.getPoint()+":"+d.getTime());
        msg.put(WSDLGetUtils.PUBLISHED_ENDPOINT_URL, "http://localhoost:8080/foo");
    }

    /**
     * Add header information to soap message.
     * 
     * @param msg Soap message
     * @throws DatatypeConfigurationException DatatypeConfigurationException
     */
    private void addheader(SoapMessage msg) throws DatatypeConfigurationException {
        ObjectFactory obf=new ObjectFactory();
        ServiceHeader serviceHeader = obf.createServiceHeader();
        Duration duration = obf.createDuration();
        TechnicalAddress techAddress = obf.createTechnicalAddress();
        
        duration.setPoint("Webservice.out");
        duration.setTime(new Date().getTime());
        techAddress.getDuration().add(duration);
        
        serviceHeader.setCreateDateTime(DatatypeFactory.newInstance().newXMLGregorianCalendar(new DateTime().toGregorianCalendar()));
        try {
            Header serheader = new Header(new QName(Constants.CORPORATESERVICE_NAMESPACE,"serviceHeader"), serviceHeader, new JAXBDataBinding(
                    ServiceHeader.class));
            
            msg.getHeaders().add(serheader);
            Header techHeader=new Header(new QName(Constants.CORPORATESERVICE_NAMESPACE,"technicalAddress"), techAddress, new JAXBDataBinding(
                    TechnicalAddress.class));
            msg.getHeaders().add(techHeader);
            msg.put(Header.HEADER_LIST, msg.getHeaders());
        } catch (JAXBException e) {
            e.printStackTrace();
        }
    }
}
