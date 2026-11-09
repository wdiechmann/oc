package dk.bankconnect.certificate;

import javax.xml.bind.annotation.XmlAccessType;
import javax.xml.bind.annotation.XmlAccessorType;
import javax.xml.bind.annotation.XmlElement;
import javax.xml.bind.annotation.XmlType;

/**
 * The Class CertificateHeader.
 */
@XmlAccessorType(XmlAccessType.FIELD)
@XmlType(name="certificateHeader")
public class CertificateHeader {

    @XmlElement(name="customernumber",required=true)
    private String customerNumber;

    /**
     * Gets the customer number.
     *
     * @return The customer number
     */
    public String getCustomerNumber() {
        return customerNumber;
    }

    /**
     * Sets the customer number.
     *
     * @param customerNumber The new customer number
     */
    public void setCustomerNumber(String customerNumber) {
        this.customerNumber = customerNumber;
    }
    

}
