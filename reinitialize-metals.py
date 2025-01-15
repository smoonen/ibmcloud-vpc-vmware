from vpc_lib import VPClib
import sshkey_tools.keys
from cryptography.hazmat.primitives.asymmetric import padding
import base64, time
import inventory

vpclib = VPClib()
rsa_priv = sshkey_tools.keys.RsaPrivateKey.from_string(inventory.rsa_private_key)

bare_metals = list(vpclib.list_bare_metal_servers(inventory.vpc_id))

# Stop all systems that are running
for bm in bare_metals :
  if bm['status'] != 'stopped' :
    # Stop the server
    vpclib.stop_bare_metal(bm['id'])

# Wait on stop to complete
print("Waiting on bare metals to stop. . .")
for bm in bare_metals :
  while bm['status'] != 'stopped' :
    time.sleep(5)
    bm = vpclib.get_bare_metal(bm['id'])

# Reinitialize all systems
for bm in bare_metals :
  init = vpclib.get_bare_metal_initialization(bm['id'])

  # Reinitialize with same key and image
  vpclib.reinitialize_bare_metal(bm['id'], init['image']['id'], init['keys'][0]['id'])

# Collect passwords
print("Waiting on passwords to populate . . .")
passwords = []
for bm in bare_metals :
  while True :
    init = vpclib.get_bare_metal_initialization(bm['id'])
    if len(init['user_accounts']) > 0 :
      break
    time.sleep(5)

  # Decrypt root password
  password = rsa_priv.key.decrypt(base64.decodebytes(bytes(init['user_accounts'][0]['encrypted_password'], 'ascii')), padding.PKCS1v15()).decode('ascii')
  passwords.append("%s_password = '%s'" % (bm['name'], password))

[print(x) for x in passwords]

