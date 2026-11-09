<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet version="1.0"
	xmlns:xsl="http://www.w3.org/1999/XSL/Transform">

	<xsl:output method="html" />
	<xsl:template match="/">
		<html>
            <meta charset="utf-8"/>
            <meta http-equiv="X-UA-Compatible" content="IE=edge"/>
            <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
            <header>
                <link rel="stylesheet" href="http://netdna.bootstrapcdn.com/bootstrap/3.0.3/css/bootstrap.min.css"/>
            </header>
            <style>
                html,body { height:100%; }
                #wrap {
                min-height: 100%;
                height: auto;
                margin: 0 auto -60px;
                padding: 0 0 60px;
                }

                #footer {
                height: 60px;
                background-color: #f5f5f5;
                }
                .container {
                width: auto;
                max-width: 1080px;
                padding: 0 15px;
                }
                .container .text-muted {
                margin: 20px 0;
                }
            </style>

			<body>
                <div id="wrap">
                    <div class="container">
                        <div class="page-header">
                            <h1>ISO20022</h1>
                        </div>
                        <p class="lead">Her vises indholdet af CAMT 54 xml filen.</p>
                        
                        
						<!--GRUPPE INFORMATION. START -->
					

                        <div class="panel panel-default">
                            <div class="panel-heading"><h4>Gruppe</h4></div>
                            <div class="panel-body">
                                <div class="row"  >
                                    <div class="col-md-4"><b>Leverance nøgle(MsgId)</b></div>
                                    <div class="col-md-4"><xsl:value-of select="/*[name()='Document']/*[name()='BkToCstmrDbtCdtNtfctn']/*[name()='GrpHdr']/*[name()='MsgId']/text()" /></div>
                                    
                                </div>
                                <div class="row">
                                    <div class="col-md-4"><b>Dannnelse af fil(CreDtTm)</b></div>
                                    <div class="col-md-4">
                                        <xsl:variable name="date">
                                            <xsl:value-of select="/*[name()='Document']/*[name()='BkToCstmrDbtCdtNtfctn']/*[name()='GrpHdr']/*[name()='CreDtTm']/text()"  />
                                        </xsl:variable>
                                          <xsl:value-of select="concat(substring($date,0,5),'-', substring($date,6,2),'-', substring($date,9,2))"/>
                                    </div>
                                </div>
                                
                            </div>
                        </div>
                        
                        
                       	<!--GRUPPE INFORMATION. SLUT -->
                       	
           
                  
                        <!--PAYMENT INFORMATION. START -->
                        
                        <div class="panel panel-default">
                            <div class="panel-heading"><h4>Payment</h4></div>
                            <div class="panel-body">
                             	 <div class="row"  >
                             		   	<div class="col-md-4"><b>Unik teknisk nøgle</b></div>
                              		  	<div class="col-md-4"><xsl:value-of select="/*[name()='Document']/*[name()='BkToCstmrDbtCdtNtfctn']/*[name()='Ntfctn']/*[name()='Id']/text()" /></div>
                             	  </div>
                             	   <div class="row"  >
                             		  	<div class="col-md-4"><b>Elektronisk nummer fra posteringen(ElctrncSeqNb)</b></div>
                              		  	<div class="col-md-4"><xsl:value-of select="/*[name()='Document']/*[name()='BkToCstmrDbtCdtNtfctn']/*[name()='Ntfctn']/*[name()='ElctrncSeqNb']/text()" /></div>
                            	   </div>
                             	   <div class="row"  >
                             		   	<div class="col-md-4"><b>Dato og tidspunkt for dannelse af udtrækket(CreDtTm)</b></div>
                              		  	<div class="col-md-4"><xsl:value-of select="/*[name()='Document']/*[name()='BkToCstmrDbtCdtNtfctn']/*[name()='Ntfctn']/*[name()='CreDtTm']/text()" /></div>
                             	  </div>
                             	   <div class="row"  >
                             		   	<div class="col-md-4"><b>Fra dato/Tidspunkt(FrDtTm)</b></div>
                              		  	<div class="col-md-4"><xsl:value-of select="/*[name()='Document']/*[name()='BkToCstmrDbtCdtNtfctn']/*[name()='Ntfctn']/*[name()='FrToDt']/*[name()='FrDtTm']/text()" /></div>
                             	  </div>
                             	  <div class="row"  >
                             		   	<div class="col-md-4"><b>Til dato/tidspunkt(ToDtTm)</b></div>
                              		  	<div class="col-md-4"><xsl:value-of select="/*[name()='Document']/*[name()='BkToCstmrDbtCdtNtfctn']/*[name()='Ntfctn']/*[name()='FrToDt']/*[name()='ToDtTm']/text()" /></div>
                             	  </div>
                             	   <div class="row"  >
                             		   	<div class="col-md-4"><b>Konto-/IBAN nr.(Acct Id)</b></div>
                              		  	<div class="col-md-4"><xsl:value-of select="/*[name()='Document']/*[name()='BkToCstmrDbtCdtNtfctn']/*[name()='Ntfctn']/*[name()='Acct']/*[name()='Id']/*[name()='Othr']/*[name()='Id']/text()" /></div>
                             	  </div>  
               					  <div class="row"  >
                             		   	<div class="col-md-4"><b>Valutakode for debetkonto(Ccy)</b></div>
                              		  	<div class="col-md-4"><xsl:value-of select="/*[name()='Document']/*[name()='BkToCstmrDbtCdtNtfctn']/*[name()='Ntfctn']/*[name()='Acct']/*[name()='Ccy']/text()" /></div>
                             	  </div>
                             	  <div class="row"  >
                             		   	<div class="col-md-4"><b>Kontonavn(Nm)</b></div>
                              		  	<div class="col-md-4"><xsl:value-of select="/*[name()='Document']/*[name()='BkToCstmrDbtCdtNtfctn']/*[name()='Ntfctn']/*[name()='Acct']/*[name()='Nm']/text()" /></div>
                             	  </div>
                             	  <div class="row"  >
                             		   	<div class="col-md-4"><b>Swiftadresse(BIC)</b></div>
                              		  	<div class="col-md-4"><xsl:value-of select="/*[name()='Document']/*[name()='BkToCstmrDbtCdtNtfctn']/*[name()='Ntfctn']/*[name()='Acct']/*[name()='Svcr']/*[name()='FinInstnId']/*[name()='BIC']/text()" /></div>
               					 </div>
                        	 </div>      
                       </div>       
                        
                      <!--PAYMENT INFORMATION. SLUT -->
                   
                        <!--TxsSummry. START -->
                        
                        <div class="panel panel-default">
                            <div class="panel-heading"><h4>TxsSummry</h4></div>
                            <div class="panel-body">
                             	 <div class="row"  >
                             		   	<div class="col-md-4"><b>Antal posteringer(NbOfNtries)</b></div>
                              		  	<div class="col-md-4"><xsl:value-of select="/*[name()='Document']/*[name()='BkToCstmrDbtCdtNtfctn']/*[name()='Ntfctn']/*[name()='TxsSummry']/*[name()='TtlNtries']/*[name()='NbOfNtries']/text()" /></div>
                             	  </div>
                             	   <div class="row"  >
                             		   	<div class="col-md-4"><b>Dety samlede beløb i kredit(Sum)</b></div>
                              		  	<div class="col-md-4"><xsl:value-of select="/*[name()='Document']/*[name()='BkToCstmrDbtCdtNtfctn']/*[name()='Ntfctn']/*[name()='TxsSummry']/*[name()='TtlNtries']/*[name()='Sum']/text()" /></div>
                             	  </div>
                             	  <div class="row"  >
                             		   	<div class="col-md-4"><b>SAmlet beløb i debet/kredit(CdtDbtInd)</b></div>
                              		  	<div class="col-md-4"><xsl:value-of select="/*[name()='Document']/*[name()='BkToCstmrDbtCdtNtfctn']/*[name()='Ntfctn']/*[name()='TxsSummry']/*[name()='TtlNtries']/*[name()='CdtDbtInd']/text()" /></div>
                             	  </div>
                             	  <div class="row"  >
                             		   	<div class="col-md-4"><b>Antal posteringer kredit(NbOfNtries)</b></div>
                              		  	<div class="col-md-4"><xsl:value-of select="/*[name()='Document']/*[name()='BkToCstmrDbtCdtNtfctn']/*[name()='Ntfctn']/*[name()='TxsSummry']/*[name()='TtlCdtNtries']/*[name()='NbOfNtries']/text()" /></div>
                             	  </div>
                             	  	  <div class="row"  >
                             		   	<div class="col-md-4"><b>Samlet sum af kreditposteringer(Sum)</b></div>
                              		  	<div class="col-md-4"><xsl:value-of select="/*[name()='Document']/*[name()='BkToCstmrDbtCdtNtfctn']/*[name()='Ntfctn']/*[name()='TxsSummry']/*[name()='TtlCdtNtries']/*[name()='Sum']/text()" /></div>
                             	  </div>
                             	  
                             	  
                        	 </div>      
                       </div>       
                        
                     <!--TxsSummry. SLUT -->
                     
                     
                      <!--PAYMENT RECORDS. START -->  
       				
       				 <xsl:for-each select="/*[name()='Document']/*[name()='BkToCstmrDbtCdtNtfctn']/*[name()='Ntfctn']/*[name()='Ntry']">
       				 
       				 	<xsl:variable name="NtryRef">
                        	<xsl:value-of select="*[name()='NtryRef']/text()" />
                      	</xsl:variable>
                      	<xsl:variable name="PaymentAmt">
                        	<xsl:value-of select="*[name()='Amt']/text()" />
                      	</xsl:variable>
                      	<xsl:variable name="PaymentCdtDbtInd">
                        	<xsl:value-of select="*[name()='CdtDbtInd']/text()" />
                      	</xsl:variable>
                      	<xsl:variable name="PaymentSts">
                        	<xsl:value-of select="*[name()='Sts']/text()" />
                      	</xsl:variable>
                      	<xsl:variable name="PaymentBookgDt">
                        	<xsl:value-of select="*[name()='BookgDt']/*[name()='Dt']/text()" />
                      	</xsl:variable>
                   		<xsl:variable name="PaymentValDt">
                        	<xsl:value-of select="*[name()='ValDt']/*[name()='Dt']/text()" />
                      	</xsl:variable>
                      	<xsl:variable name="AcctSvcrRef">
                        	<xsl:value-of select="*[name()='AcctSvcrRef']/text()" />
                      	</xsl:variable>
                      	<xsl:variable name="NtryDtlsAcctSvcrRef">
                        	<xsl:value-of select="*[name()='NtryDtls']/*[name()='TxDtls']/*[name()='Refs']/*[name()='AcctSvcrRef']/text()" />
                      	</xsl:variable>
                      	<xsl:variable name="NtryDtlsInstrId">
                        	<xsl:value-of select="*[name()='NtryDtls']/*[name()='TxDtls']/*[name()='Refs']/*[name()='InstrId']/text()" />
                      	</xsl:variable>
      					<xsl:variable name="InstdAmt">
                        	<xsl:value-of select="*[name()='NtryDtls']/*[name()='TxDtls']/*[name()='Refs']/*[name()='InstdAmt']/*[name()='Amt']/text()" />
                      	</xsl:variable>
    
    
       				
                   		 <table class="table table-bordered">
                        	<thead>
                                                  
                            	<xsl:if test="$NtryRef and (string($NtryRef))">
                             	  	<th>Unikt løbenr.</th>
                             	</xsl:if>
                             	<xsl:if test="$PaymentAmt and (string($PaymentAmt))">
                             	  	<th>Beløb</th>
                             	</xsl:if>
                             	<xsl:if test="$PaymentCdtDbtInd and (string($PaymentCdtDbtInd))">
                             	  	<th>Posteringer i debet/kredit</th>
                             	</xsl:if>
                             	<xsl:if test="$PaymentSts and (string($PaymentSts))">
                             	  	<th>Bogføringsstatus(bogført)</th>
                             	</xsl:if>
                             	<xsl:if test="$PaymentBookgDt and (string($PaymentBookgDt))">
                             	  	<th>Bogføringsstatus</th>
                             	</xsl:if>
                             	<xsl:if test="$PaymentValDt and (string($PaymentValDt))">
                             	  	<th>Valørdato</th>
                             	</xsl:if>
                             	<xsl:if test="$AcctSvcrRef and (string($AcctSvcrRef))">
                             	  	<th>Posteringsid. Camt/pain</th>
                             	</xsl:if>
                             	<xsl:if test="$NtryDtlsAcctSvcrRef and (string($NtryDtlsAcctSvcrRef))">
                             	  	<th>Løbenr. (NtryDtlsAcctSvcrRef)</th>
                             	</xsl:if>
                             	<xsl:if test="$NtryDtlsInstrId and (string($NtryDtlsInstrId))">
                             	  	<th>NtryDtlsInstrId</th>
                             	</xsl:if>
                             	<xsl:if test="$InstdAmt and (string($InstdAmt))">
                             	  	<th>InstdAmt</th>
                             	</xsl:if>
                             	
                             	
                        	</thead>
                        
                        	<tbody>
                           
                             	<tr>
                              		<xsl:if test="($NtryRef) and (string($NtryRef))">
                             		 		<td> <xsl:value-of select="$NtryRef"/> </td>
                             		</xsl:if>
                             		<xsl:if test="($PaymentAmt) and (string($PaymentAmt))">
                             		 		<td>
                             		 			<xsl:value-of select="$PaymentAmt"/> 
                             		 			<xsl:text> </xsl:text>
                                    			<xsl:value-of select="*[name()='Amt']/@Ccy"/>
                             		 		</td>
                             		</xsl:if>
                             		<xsl:if test="($PaymentCdtDbtInd) and (string($PaymentCdtDbtInd))">
                             		 		<td> <xsl:value-of select="$PaymentCdtDbtInd"/> </td>
                             		</xsl:if>
                             		<xsl:if test="($PaymentSts) and (string($PaymentSts))">
                             		 		<td> <xsl:value-of select="$PaymentSts"/> </td>
                             		</xsl:if>
                             		<xsl:if test="($PaymentBookgDt) and (string($PaymentBookgDt))">
                             		 		<td> <xsl:value-of select="$PaymentBookgDt"/> </td>
                             		</xsl:if>
                             		<xsl:if test="($PaymentValDt) and (string($PaymentValDt))">
                             		 		<td> <xsl:value-of select="$PaymentValDt"/> </td>
                             		</xsl:if>
                             		<xsl:if test="($AcctSvcrRef) and (string($AcctSvcrRef))">
                             		 		<td> <xsl:value-of select="$AcctSvcrRef"/> </td>
                             		</xsl:if>
                             		<xsl:if test="($NtryDtlsAcctSvcrRef) and (string($NtryDtlsAcctSvcrRef))">
                             		 		<td> <xsl:value-of select="$NtryDtlsAcctSvcrRef"/> </td>
                             		</xsl:if>
                             		<xsl:if test="($NtryDtlsInstrId) and (string($NtryDtlsInstrId))">
                             		 		<td> <xsl:value-of select="$NtryDtlsInstrId"/> </td>
                             		</xsl:if>
                             		<xsl:if test="($InstdAmt) and (string($InstdAmt))">
                             		 		<td> 
                             		 			<xsl:value-of select="$InstdAmt"/>
                             		 			<xsl:text> </xsl:text>
                                    			<xsl:value-of select="*[name()='NtryDtls']/*[name()='TxDtls']/*[name()='Refs']/*[name()='InstdAmt']/*[name()='Amt']/@Ccy"/>
                             		 		 </td>
                             		</xsl:if>
                             	                             		
                             		
                                </tr>
                            
                            </tbody>
                    
                    	</table>
                    
                    </xsl:for-each>
                    
                    
                     <!--PAYMENT RECORDS. SLUT -->  
                    
                    </div>
                </div>

                <div id="footer">
                    <div class="container">
                        <p class="text-muted">(c) BankConnect 2014</p>
                    </div>
                </div>

            </body>
		</html>
	</xsl:template>

</xsl:stylesheet>
