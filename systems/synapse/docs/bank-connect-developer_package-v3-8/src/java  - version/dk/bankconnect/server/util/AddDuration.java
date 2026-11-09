package dk.bankconnect.server.util;

import java.util.Calendar;
import javax.xml.ws.Holder;

import org.apache.commons.logging.Log;
import org.apache.commons.logging.LogFactory;

import dk.bankconnect.schema._2014.Duration;
import dk.bankconnect.schema._2014.TechnicalAddress;

// TODO: Auto-generated Javadoc
/**
 * The Class AddDuration.
 * 
 * @author bdusmo
 * 
 */

public class AddDuration {

    /**
     * Initialize duration point and add it to technical address.
     * Note that duration points are only added if the client did add a duration point to the request.
     * 
     * @param technicalAddress
     *            the technical address containing IpAddress, ipPort and
     *            Duration points.
     * @param point
     *            A brief description of where the duration point was set.
     */
    public static void Add(Holder<TechnicalAddress> technicalAddress, String point) {
        Log logger = LogFactory.getFactory().getInstance(AddDuration.class);

        if (technicalAddress.value == null) {
            technicalAddress.value = new TechnicalAddress();
        }
    
        if (technicalAddress.value.getDuration().size() > 0) {
            if (logger.isDebugEnabled()) {
                logger.debug("Initialize duration point: '" + point + "' and add it to technical address");
            }

            Duration duration = new Duration();
            duration.setTime(Calendar.getInstance().getTimeInMillis());
            duration.setPoint(point);
            technicalAddress.value.getDuration().add(duration);
            
        } else if (logger.isDebugEnabled()) {
            logger.debug("No duration point were added to technical address");
        }
    }
    
    /**
     * Initialize duration point and add it to technical address.
     * This method adds a duration point the request. 
     * 
     * @param technicalAddress
     *            the technical address containing IpAddress, ipPort and
     *            Duration points.
     * @param point
     *            A brief description of where the duration point was set.
     */
    public static void ForceAdd(Holder<TechnicalAddress> technicalAddress, String point) {
        Log logger = LogFactory.getFactory().getInstance(AddDuration.class);

        if (technicalAddress.value == null) {
            technicalAddress.value = new TechnicalAddress();
        }

        if (logger.isDebugEnabled()) {
            logger.debug("Initialize duration point: '" + point + "' and add it to technical address");
        }

        Duration duration = new Duration();
        duration.setTime(Calendar.getInstance().getTimeInMillis());
        duration.setPoint(point);
        technicalAddress.value.getDuration().add(duration);
    }
}
