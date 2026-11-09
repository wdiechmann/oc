package dk.bankconnect.server;

import java.util.List;
import java.util.Map;

import org.apache.cxf.binding.soap.Soap11;
import org.apache.cxf.binding.soap.SoapMessage;
import org.apache.cxf.binding.soap.interceptor.AbstractSoapInterceptor;
import org.apache.cxf.binding.soap.interceptor.SoapActionInInterceptor;
import org.apache.cxf.helpers.CastUtils;
import org.apache.cxf.interceptor.Fault;
import org.apache.cxf.message.Message;
import org.apache.cxf.phase.Phase;

/**
 * The RemoveSOAPActionInterceptor class extends 
 * the AbstractSoapInterceptor class. 
 */
public class RemoveSOAPActionInterceptor extends AbstractSoapInterceptor {

    /**
     * Constructor.
     */
    public RemoveSOAPActionInterceptor() {
        super(Phase.READ);
        addBefore(SoapActionInInterceptor.class.getName());
    }

    /**
     * Handle soap message.
     * 
     * @param message
     * @throws Fault @see org.apache.cxf.interceptor.Fault
     */
    @Override
    public void handleMessage(SoapMessage message) throws Fault {
        if (message.getVersion() instanceof Soap11) {
            Map<String, List<String>> headers = CastUtils.cast((Map) message.get(Message.PROTOCOL_HEADERS));
            headers.remove("SOAPAction");
        }
    }
}

