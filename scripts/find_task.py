"""Find Paperclip task t_0c619d4e and return its title, description, and TODO from knowledge base."""
import json, subprocess, sys

# Known company shortcut from session memory
COMPANY_ID = 'ea4bb5d7-6c08-4b2f-b240-685e95efbf47'

def paperclip_cli(*args, timeout=15):
    cmd = ['npx', '-y', '-p', 'paperclipai', '-p', 'drizzle-orm',
           'paperclipai'] + list(args)
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    return r.stdout.strip(), r.stderr.strip(), r.returncode

def curl_json(url):
    r = subprocess.run(['curl','-s',url], capture_output=True, text=True, timeout=10)
    return json.loads(r.stdout)

# Get company info
out, err, rc = paperclip_cli('company','get',COMPANY_ID)
print(f"[COMPANY-GET] rc={rc}")
print(out[:400] if out else err[:400])
print()

# Find the task via the Paperclip REST API directly on running server
try:
    info = curl_json(f'http://127.0.0.1:3100/api/companies/{COMPANY_ID}')
    print(f"[COMPANY-API] name={info.get('name','?')}")
except Exception as e:
    print(f"[COMPANY-API] error: {e}")

# Find issues
try:
    issues = curl_json(f'http://127.0.0.1:3100/api/companies/{COMPANY_ID}/issues?limit=50')
    print(f"[ISSUES-API] count={issues.get('totalCount','?')}")
    if 'issues' in issues:
        for i in issues['issues'][:3]:
            print(f"  {i.get('identifier','?')}: {i.get('title','?')}")
except Exception as e:
    print(f"[ISSUES-API] error: {e}")
