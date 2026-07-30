
variant_name    = "noisy"
# all mc switches are false, ie the deployment is compliant

# legitimate periodic SP secret rotation
enable_credential_rotation = true 

# adds an extra but still restricted inbound rule
enable_nsg_routine_update = true 

# autorotation event in Key vault
enable_tls_cert_renewal = true 
