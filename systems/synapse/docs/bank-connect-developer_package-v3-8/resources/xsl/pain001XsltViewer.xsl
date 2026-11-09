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
                        <p class="lead">Her vises indholdet af iso xml filen.</p>
                        
                        
                        
						<!--GRUPPE INFORMATION. START -->
					

                        <div class="panel panel-default">
                            <div class="panel-heading"><h4>Gruppe</h4></div>
                            <div class="panel-body">
                                <div class="row"  >
                                    <div class="col-md-4"><b>Leverance nøgle(MsgId)</b></div>
                                    <div class="col-md-4"><xsl:value-of select="/*[name()='Document']/*[name()='CstmrCdtTrfInitn']/*[name()='GrpHdr']/*[name()='MsgId']/text()" /></div>
                                    
                                </div>
                                <div class="row">
                                    <div class="col-md-4"><b>Dannnelse af fil(CreDtTm)</b></div>
                                    <div class="col-md-4">
                                        <xsl:variable name="date">
                                            <xsl:value-of select="/*[name()='Document']/*[name()='CstmrCdtTrfInitn']/*[name()='GrpHdr']/*[name()='CreDtTm']/text()"  />
                                        </xsl:variable>
                                          <xsl:value-of select="concat(substring($date,0,5),'-', substring($date,6,2),'-', substring($date,9,2))"/>
                                    </div>
                                </div>
                                  <div class="row"  >
                                    <div class="col-md-4"><b>Antal transaktioner(NbOfTxs)</b></div>
                                    <div class="col-md-4"><xsl:value-of select="/*[name()='Document']/*[name()='CstmrCdtTrfInitn']/*[name()='GrpHdr']/*[name()='NbOfTxs']/text()" /></div>
                                </div>
                                  <div class="row"  >
                                    <div class="col-md-4"><b>Kundens id</b></div>
                                    <div class="col-md-4"><xsl:value-of select="/*[name()='Document']/*[name()='CstmrCdtTrfInitn']/*[name()='GrpHdr']/*[name()='InitgPty']/*[name()='Id']/*[name()='OrgId']/*[name()='Othr']/*[name()='Id']/text()" /></div>
                                </div>
                                
                            </div>
                        </div>
                        
                        
                       	<!--GRUPPE INFORMATION. SLUT -->
                        
                        
                        <!--PAYMENT INFORMATION. START -->
                        
                        <div class="panel panel-default">
                            <div class="panel-heading"><h4>Payment info</h4></div>
                            <div class="panel-body">
                              <div class="row"  >
                             	   	<div class="col-md-4"><b>Debet nøgle(PmtInfId)</b></div>
                              	  	<div class="col-md-4"><xsl:value-of select="/*[name()='Document']/*[name()='CstmrCdtTrfInitn']/*[name()='PmtInf']/*[name()='PmtInfId']/text()" /></div>
                               </div>
                                <div class="row"  >
                                    <div class="col-md-4"><b>Betalings Type Chk/Trf (PmtMtd)</b></div>
                                    <div class="col-md-4"><xsl:value-of select="/*[name()='Document']/*[name()='CstmrCdtTrfInitn']/*[name()='PmtInf']/*[name()='PmtMtd']/text()" /></div>
                                </div>
                                <div class="row"  >
                                    <div class="col-md-4"><b>Ekspeditions dato(ReqdExctnDt)</b></div>
                                    <div class="col-md-4"><xsl:value-of select="/*[name()='Document']/*[name()='CstmrCdtTrfInitn']/*[name()='PmtInf']/*[name()='ReqdExctnDt']/text()" /></div>
                                </div>
                                
                                 <xsl:variable name="dbtrNm">
                                   		<xsl:value-of select="/*[name()='Document']/*[name()='CstmrCdtTrfInitn']/*[name()='PmtInf']/*[name()='Dbtr']/*[name()='Nm']/text()" />
                                 </xsl:variable>
                                
								<xsl:if test="$dbtrNm">
                                	<div class="row"  >
                                 	   <div class="col-md-4"><b>Debitor navn(Dbtr Nm)</b></div>
                                 	   <div class="col-md-4"><xsl:value-of select="/*[name()='Document']/*[name()='CstmrCdtTrfInitn']/*[name()='PmtInf']/*[name()='Dbtr']/*[name()='Nm']/text()" /></div>
                               	 </div>
                                </xsl:if>
                                
                                 
                                 <xsl:variable name="dbtrCtry">
                                   		<xsl:value-of select="/*[name()='Document']/*[name()='CstmrCdtTrfInitn']/*[name()='PmtInf']/*[name()='Dbtr']/*[name()='PstlAdr']/*[name()='Ctry']/text()" />
                                 </xsl:variable>
                                
                                <xsl:if test="$dbtrCtry">
                              	  <div class="row"  >
                                	    <div class="col-md-4"><b>Debitor land(Dbtr ctry)</b></div>
                                	    <div class="col-md-4"><xsl:value-of select="/*[name()='Document']/*[name()='CstmrCdtTrfInitn']/*[name()='PmtInf']/*[name()='Dbtr']/*[name()='PstlAdr']/*[name()='Ctry']/text()" /></div>
                                	</div>
                                 </xsl:if>
                                
                               
                                
								<!-- dbtrAcct -->
                                <xsl:variable name="dbtrAcct1">
                                           <xsl:value-of select="/*[name()='Document']/*[name()='CstmrCdtTrfInitn']/*[name()='PmtInf']/*[name()='DbtrAcct']/*[name()='Id']/*[name()='Othr']/*[name()='Id']/text()" />
                                 </xsl:variable>
                                  <xsl:variable name="dbtrAcct2">
                                           <xsl:value-of select="/*[name()='Document']/*[name()='CstmrCdtTrfInitn']/*[name()='PmtInf']/*[name()='DbtrAcct']/*[name()='Id']/*[name()='IBAN']/text()" />
                                 </xsl:variable>
                                
                                
								<!--      DbtrAcct Id -->
                                
                                 <div class="row"  >
                                 	 <div class="col-md-4"><b>Debitor konto BBAN/IBAN(DbtrAcct)</b></div>
                                 	 <div class="col-md-4">
										<xsl:if test="$dbtrAcct1">
                                	    	<xsl:value-of select="/*[name()='Document']/*[name()='CstmrCdtTrfInitn']/*[name()='PmtInf']/*[name()='DbtrAcct']/*[name()='Id']/*[name()='Othr']/*[name()='Id']/text()" />
                               		 	</xsl:if>
										<xsl:if test="$dbtrAcct2">
                                	    	<xsl:value-of select="/*[name()='Document']/*[name()='CstmrCdtTrfInitn']/*[name()='PmtInf']/*[name()='DbtrAcct']/*[name()='Id']/*[name()='IBAN']/text()" />
                               		 	</xsl:if>
                               		 </div>
                                 </div>
                                
                                 <div class="row"  >
                                    <div class="col-md-4"><b>Debitor kontos mønt(DbtrAcct Ccy)</b></div>
                                    <div class="col-md-4"><xsl:value-of select="/*[name()='Document']/*[name()='CstmrCdtTrfInitn']/*[name()='PmtInf']/*[name()='DbtrAcct']/*[name()='Ccy']/text()" /></div>
                                 </div>
                                
                                
                                  <xsl:variable name="dbtrAgtBic">
                                   		<xsl:value-of select="/*[name()='Document']/*[name()='CstmrCdtTrfInitn']/*[name()='PmtInf']/*[name()='DbtrAgt']/*[name()='FinInstnId']/*[name()='BIC']/text()" />
                                 </xsl:variable>
                                
                                
                               
                                <xsl:if test="$dbtrAgtBic  and (string($dbtrAgtBic))">
                               		 <div class="row"  >
                                    	<div class="col-md-4"><b>Swift adresse afsender(DbtrAgt BIC)</b></div>
                                   		<div class="col-md-4"><xsl:value-of select="/*[name()='Document']/*[name()='CstmrCdtTrfInitn']/*[name()='PmtInf']/*[name()='DbtrAgt']/*[name()='FinInstnId']/*[name()='BIC']/text()" /></div>
                                	</div>
                                </xsl:if>
                                
                                <xsl:variable name="SvcLvl">
                                   		<xsl:value-of select="/*[name()='Document']/*[name()='CstmrCdtTrfInitn']/*[name()='PmtInf']/*[name()='PmtTpInf']/*[name()='SvcLvl']/*[name()='Cd']/text()" />
                                 </xsl:variable>
                                 
                                  <xsl:variable name="LclInstrm">
                                   		<xsl:value-of select="/*[name()='Document']/*[name()='CstmrCdtTrfInitn']/*[name()='PmtInf']/*[name()='PmtTpInf']/*[name()='LclInstrm']/*[name()='Cd']/text()" />
                                 </xsl:variable>
                               
                                
                                 <xsl:if test="$SvcLvl or $LclInstrm">
                                     <xsl:if test="(string($SvcLvl)) or (string($LclInstrm))">
                                      <div class="row"  >
                                      	<div class="col-md-4"><b>Clearings type:</b></div>
                                 			<div class="col-md-4">
                                 				<xsl:value-of select="$SvcLvl" />
                                 				<xsl:text> </xsl:text>
                                 				<xsl:value-of select="$LclInstrm" />
                                          	</div>	
                                       </div>  	
                                     </xsl:if>
                                 </xsl:if>
                                
                                  
                                 <xsl:variable name="Ctgypurp">
                                   		<xsl:value-of select="/*[name()='Document']/*[name()='CstmrCdtTrfInitn']/*[name()='PmtInf']/*[name()='PmtTpInf']/*[name()='CtgyPurp']/*[name()='Cd']/text()" />
                                 </xsl:variable>
                                
                                  <xsl:if test="$Ctgypurp">
                                     <xsl:if test="(string($Ctgypurp))">
                                      <div class="row">
                                      	<div class="col-md-4"><b>Payment:</b></div>
                                 			<div class="col-md-4">
                                          		<xsl:value-of select="$Ctgypurp" />
                                          	</div>	
                                       </div>  	
                                     </xsl:if>
                                 </xsl:if>
                             
                             
                                
                            </div>
                        </div>
                        
                        
                      <!--PAYMENT INFORMATION. SLUT -->
                      
                      
                      
                        
                      <!--PAYMENT RECORDS. START -->  
       				
       				 <xsl:for-each select="/*[name()='Document']/*[name()='CstmrCdtTrfInitn']/*[name()='PmtInf']/*[name()='CdtTrfTxInf']">
       				 
       				 <xsl:variable name="kreditorNummer">
                                		<xsl:value-of select="*[name()='CdtrAcct']/*[name()='Id']/*[name()='Othr']/*[name()='Id']/text()" />
                      </xsl:variable>
                      
                      <xsl:variable name="kreditorNummer1">
                               		<xsl:value-of select="*[name()='CdtrAcct']/*[name()='Id']/*[name()='IBAN']/text()" />
                      </xsl:variable>
                      
                      
                      <xsl:variable name="kreditornavn">
                               		<xsl:value-of select="*[name()='Cdtr']/*[name()='Nm']/text()" />
                      </xsl:variable>
                      
                      <xsl:variable name="kreditorAdresse">
                               		<xsl:value-of select="*[name()='Cdtr']/*[name()='PstlAdr']/*[name()='AdrLine']/text()" />
                      </xsl:variable>
                      
                      <xsl:variable name="kreditorAdresse1">
                               		<xsl:value-of select="*[name()='Cdtr']/*[name()='PstlAdr']/*[name()='StrtNm']/text()" />
                      </xsl:variable>
                      
                                       
           			 <xsl:variable name="egenBilagRef">
           			 		  		<xsl:value-of select="*[name()='RmtInf']/*[name()='Strd']/*[name()='RfrdDocInf']/*[name()='Nb']/text()"  />
                     </xsl:variable>
		            					
                      
                      <xsl:variable name="betalingsIdent">
                               		   <xsl:value-of select="*[name()='RmtInf']/*[name()='Strd']/*[name()='CdtrRefInf']/*[name()='Ref']/text()"  />
                      </xsl:variable>
                      
                      <xsl:variable name="advisTekst">
                               		   <xsl:value-of select="*[name()='RmtInf']/*[name()='Ustrd']/text()"/>
                      </xsl:variable>
                      
                      <xsl:variable name="postKreditor">
                               		   <xsl:value-of select="*[name()='Purp']/*[name()='Prtry']/text()"  />
                      </xsl:variable>
                      
                      <xsl:variable name="kredIndDeb">
                               		   <xsl:value-of select="*[name()='RmtInf']/*[name()='Strd']/*[name()='RfrdDocInf']/*[name()='Nb']/text()"/>
                      </xsl:variable>
                      
                      <xsl:variable name="swiftModt">
                               		 <xsl:value-of select="*[name()='CdtrAgt']/*[name()='FinInstnId']/*[name()='BIC']/text()" />
                      </xsl:variable>
                      
                      <xsl:variable name="leveringsMetode">
                               		 <xsl:value-of select="*[name()='ChqInstr']/*[name()='DlvryMtd']/*[name()='Cd']/text()" />
                      </xsl:variable> 
                     
                     
               
       				
                    <table class="table table-bordered">
                        <thead>
                             
                             <th>End to end ID</th>
                            
                             <th>Amount</th>
                           
                           	<xsl:if test="($kreditorNummer) or ($kreditorNummer1)">
                             	<xsl:if test="(string($kreditorNummer))or (string($kreditorNummer1))">
                             	  	<th>Kreditor nummer/Kreditor konto</th>
                             	</xsl:if>
                            </xsl:if>
                            
                              <xsl:if test="($kreditornavn) and (string($kreditornavn))">
                             	  <th>kreditor navn/posteringstekst til debitor</th>
                             </xsl:if>
                             
                      
                             <xsl:if test="($kreditorAdresse) and (string($kreditorAdresse))">
                             	  <th>Kreditor adresse</th>
                             </xsl:if>
                            
                              <xsl:if test="($kreditorAdresse1) and (string($kreditorAdresse1))">
                             	  <th>Kreditor adresse</th>
                             </xsl:if>
                            
                              <xsl:if test="($egenBilagRef) and (string($egenBilagRef))">
                             	  <th>Egen bilagsreference(DEBI)</th>
                             </xsl:if>
                           
                           	  <xsl:if test="($betalingsIdent) and (string($betalingsIdent))">
                             	  <th>Kortart/Betalingsident</th>
                             </xsl:if>
                           
                             <xsl:if test="($advisTekst) and (string($advisTekst))">
                             	  <th>Adviserings tekst</th>
                             </xsl:if>
                           
                             <xsl:if test="($postKreditor) and (string($postKreditor))">
                             	  <th>Posterings tekst kreditor</th>
                             </xsl:if>
                           
                             <xsl:if test="($kredIndDeb) and (string($kredIndDeb))">
                             	  <th>Betalings detail opl.</th>
                             </xsl:if>
                           
                          	 <xsl:if test="($swiftModt) and (string($swiftModt))">
                             	  <th>Swiftadresse modtager</th>
                             </xsl:if>
                             
                             <xsl:if test="($leveringsMetode) and (string($leveringsMetode))">
                             	  <th>Leverings metode</th>
                             </xsl:if>
                             
                             <th>Payment</th>
                        </thead>
                        
                        <tbody>
                           
                                <tr>
                                <td>
                                    <xsl:value-of select="*[name()='PmtId']/*[name()='EndToEndId']/text()" />
                                </td>
                             
                                 <td>
                                    <xsl:value-of select="*[name()='Amt']/*[name()='InstdAmt']/text()"/>
                                    <xsl:text> </xsl:text>
                                    <xsl:value-of select="*[name()='Amt']/*[name()='InstdAmt']/@Ccy"/>
                                 </td>
                             
                              <xsl:if test="($kreditorNummer) or ($kreditorNummer1)">
                             	<xsl:if test="(string($kreditorNummer))or (string($kreditorNummer1))">
                                	<td>
                                    	<xsl:value-of select="$kreditorNummer"/>
                                    	<xsl:value-of select="$kreditorNummer1"/>
                               		 </td>
                           		 </xsl:if>
                           	    </xsl:if>	
                           	  
                           	 <xsl:if test="($kreditornavn) and (string($kreditornavn))">
                             	 	<td> <xsl:value-of select="$kreditornavn"/> </td>
                             </xsl:if>
                             
                            <xsl:if test="($kreditorAdresse) and (string($kreditorAdresse))">
                             	 	<td> 
                             	 	   <xsl:for-each select="*[name()='Cdtr']/*[name()='PstlAdr']/*[name()='AdrLine']">
                             	 			  <xsl:value-of select="text()"/>
                             	 			  <xsl:text> </xsl:text>
                             	 	   	</xsl:for-each>	
                             	 	  
                             	 	
                             	 	 </td>
                             </xsl:if>
                             
                             <xsl:if test="($kreditorAdresse1) and (string($kreditorAdresse1))">
                                    	 	<td> 
                                    	 		 <xsl:value-of select="*[name()='Cdtr']/*[name()='PstlAdr']/*[name()='StrtNm']/text()" />
                           						 <xsl:text> </xsl:text>
                           						<xsl:value-of select="*[name()='Cdtr']/*[name()='PstlAdr']/*[name()='BldgNb']/text()" />
                           						 <xsl:text> </xsl:text>
                           						 <xsl:value-of select="*[name()='Cdtr']/*[name()='PstlAdr']/*[name()='PstCd']/text()" />
                           						 <xsl:text> </xsl:text>
                          						<xsl:value-of select="*[name()='Cdtr']/*[name()='PstlAdr']/*[name()='TwnNm']/text()" />
                           						 <xsl:text> </xsl:text>
                           						 <xsl:value-of select="*[name()='Cdtr']/*[name()='PstlAdr']/*[name()='Ctry']/text()" />
                           					</td>
                             </xsl:if>  
                                          
                                          
                             
                           	   
                           	   	<xsl:if test="$egenBilagRef and (string($egenBilagRef))">
                          			<td>
                          				<xsl:for-each select="*[name()='RmtInf']/*[name()='Strd']/*[name()='RfrdDocInf']">
                          				   <xsl:variable name="kredIndDebType">
                            		   			<xsl:value-of select="*[name()='Tp']/*[name()='CdOrPrtry']/*[name()='Prtry']/text()"/>
                     					   </xsl:variable>	
                      					   <xsl:choose>
           							 			<xsl:when test="contains($kredIndDebType,'DEBI')">
           							 				<xsl:value-of select="*[name()='Nb']/text()"/>
		            							</xsl:when>
		            							<xsl:otherwise>
		           								</xsl:otherwise>
             								</xsl:choose>
		                             	 </xsl:for-each>
									</td>
								</xsl:if>
                           	    
                             	
                             	 <xsl:if test="$betalingsIdent and (string($betalingsIdent))">
                             	  	<td>
                                    	<xsl:value-of select="$betalingsIdent"/>
                               		 </td>
                             	</xsl:if>
                             	 
                             	 
                             	<xsl:if test="($advisTekst) and string($advisTekst)">
                             	  	<td>
                             	  		<xsl:for-each select="*[name()='RmtInf']/*[name()='Ustrd']">
                             	  	              <xsl:value-of select="text()"/>
                                   	 	</xsl:for-each>
                               		 </td>
                             	</xsl:if>
                             	
                              <xsl:if test="($postKreditor) and (string($postKreditor))">
                             	  	<td>
                                    	<xsl:value-of select="$postKreditor"/>
                               		 </td>
                             	</xsl:if>
                          
                          		<xsl:if test="$kredIndDeb and (string($kredIndDeb))">
                          			<td>
                          				<xsl:for-each select="*[name()='RmtInf']/*[name()='Strd']/*[name()='RfrdDocInf']">
                          					<xsl:variable name="kredIndDebType">
                                		   		<xsl:value-of select="*[name()='Tp']/*[name()='CdOrPrtry']/*[name()='Prtry']/text()"/>
                      						</xsl:variable>
                      					   
                      					   <xsl:choose>
           							 			<xsl:when test="contains($kredIndDebType,'CRED')">
           							 				Kreditors id af debitor(CRED):
		            							</xsl:when>
           							 			<xsl:when test="contains($kredIndDebType,'PRIM')">
           							 			    Faktura nummer(PRIM):
		            							</xsl:when>
           							 			<xsl:when test="contains($kredIndDebType,'DEBI')">
           							 			   Debotors id af betalingen(DEBI):
		            							</xsl:when>
		            							<xsl:when test="contains($kredIndDebType,'EPNU')">
           							 			   Medarbejder nummer(EPNU):
		            							</xsl:when>
		            							<xsl:otherwise>
		           								</xsl:otherwise>
             								</xsl:choose>
                               		        <xsl:value-of select="*[name()='Nb']/text()"/>
                               		     	<p></p>
		                             	 </xsl:for-each>
									</td>
								</xsl:if>
								
								<xsl:if test="($swiftModt) and (string($swiftModt))">
                             	  	<td>
                                    	<xsl:value-of select="$swiftModt"/>
                               		 </td>
                             	</xsl:if>
                             	
                             	<xsl:if test="($leveringsMetode) and (string($leveringsMetode))">
                             		<td>
                                    	<xsl:value-of select="$leveringsMetode"/>
                               		 </td>
                             	</xsl:if>
                             	
                             	
								 <xsl:variable name="paymentType">
                                            <xsl:value-of select="*[name()='RmtInf']/*[name()='Strd']/*[name()='CdtrRefInf']/*[name()='Ref']/text()"  />
                                 </xsl:variable>

								
								 <xsl:variable name="pmtMtd">
                                           <xsl:value-of select="/*[name()='Document']/*[name()='CstmrCdtTrfInitn']/*[name()='PmtInf']/*[name()='PmtMtd']/text()" />
                                 </xsl:variable>
          
				
								 <xsl:variable name="Prtry">
                                           <xsl:value-of select="/*[name()='Document']/*[name()='CdtrAcct']/*[name()='Id']/*[name()='SchmeNm']/*[name()='Prtry']/text()" />
                                 </xsl:variable>
		      
                                 <xsl:variable name="InstrForDbtrAgt">
                                            <xsl:value-of select="*[name()='InstrForDbtrAgt']/text()"  />
                                 </xsl:variable>
                                 
                                 
                                 <xsl:variable name="SvcLvl">
                                            <xsl:value-of select="*[name()='PmtTpInf']/*[name()='SvcLvl']/*[name()='Cd']/text()"  />
                                 </xsl:variable>
                                 
                                  <xsl:variable name="LclInstrm">
                                            <xsl:value-of select="*[name()='PmtTpInf']/*[name()='LclInstrm']/*[name()='Cd']/text()"  />
                                 </xsl:variable>
                                 
                                 <xsl:variable name="ChrgBr">
                                            <xsl:value-of select="*[name()='ChrgBr']/text()"  />
                                 </xsl:variable>
                                              
                                 
                                 <xsl:choose>
           							 <xsl:when test="contains(substring($paymentType,1,2),'01')">
           						     	 <td>
           						     	 	Giro Indbetalingskort 01
           						     	 </td>
            						</xsl:when>
            						 <xsl:when test="contains(substring($paymentType,1,2),'04')">
           						     	 <td>
           						     	 	Giro Indbetalingskort04           						     	 	
           						     	 </td>
            						</xsl:when>
            						 <xsl:when test="contains(substring($paymentType,1,2),'15')">
           						     	 <td>
           						     	 	Giro Indbetalingskort15
           						     	 </td>
            						</xsl:when>
            						 <xsl:when test="contains(substring($paymentType,1,2),'71')">
           						     	 <td>
           						     	 	Indbetalingskort FI-71
           						     	 </td>
            						</xsl:when>
            						 <xsl:when test="contains(substring($paymentType,1,2),'73')">
           						     	 <td>
           						     	 	Indbetalingskort FI-73
           						     	 </td>
            						</xsl:when>
            						 <xsl:when test="contains(substring($paymentType,1,2),'75')">
           						     	 <td>
           						     	 	Indbetalingskort FI-75
           						     	 </td>
            						</xsl:when>
           							<xsl:otherwise>
                						<td>
                                			<xsl:if test="$LclInstrm or $SvcLvl"> 
                                			    <xsl:if test="string($LclInstrm) or string($SvcLvl)"> 
                                 					<p>	
                                 					<xsl:text>Clearings type:</xsl:text>
                                 					</p>
                                 					<xsl:value-of select="$SvcLvl" />
                                 					 <xsl:text> </xsl:text>
                                 					<xsl:value-of select="$LclInstrm" />
                                 				</xsl:if>
                                 			</xsl:if>		
                              	 			<xsl:if test="$InstrForDbtrAgt and  string($InstrForDbtrAgt)">
                              	 				<p>
                              					<xsl:text>InstrForDbtrAgt:</xsl:text>
                              					</p>
                                 				<xsl:value-of select="$InstrForDbtrAgt" />
                                 			</xsl:if>	
                                 			<xsl:if test="$ChrgBr and  string($ChrgBr)">
                              	 				<p>
                              					<xsl:text>Omkostninger:</xsl:text>
                              					</p>
                                 				<xsl:value-of select="$ChrgBr" />
                                 			</xsl:if>	
                                 			
                                 			
                                 			
   							 			</td>
           							</xsl:otherwise>
           						</xsl:choose>
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
