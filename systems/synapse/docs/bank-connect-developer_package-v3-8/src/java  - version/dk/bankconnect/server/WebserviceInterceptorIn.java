package dk.bankconnect.server;

import org.apache.commons.logging.Log;
import org.apache.commons.logging.LogFactory;
import org.apache.cxf.binding.soap.SoapMessage;
import org.apache.cxf.binding.soap.interceptor.AbstractSoapInterceptor;
import org.apache.cxf.interceptor.Fault;
import org.apache.cxf.phase.Phase;

import dk.bankconnect.schema._2014.Duration;

/**
 * The WebserviceInterceptorIn class extends
 * the AbstractSoapInterceptor class.
 */
public class WebserviceInterceptorIn extends AbstractSoapInterceptor {
    private Log logger = LogFactory.getFactory().getInstance(WebserviceInterceptorIn.class);


    /**
     * Constructor.
     */
    public WebserviceInterceptorIn() {
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
        addheader(msg);
        Duration duration = new Duration();
        duration.setPoint("incoming");
        duration.setTime(System.currentTimeMillis());
        msg.getExchange().put("duration",duration );
    }


    private void addheader(SoapMessage msg) {
       //FIXME: Add incoming durationpoint
    }
}
