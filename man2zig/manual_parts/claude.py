import requests
import json

def read_file(filename):
    with open(filename, 'r') as f:
        return f.read().strip()

def query_claude(api_key, prompt):
    url = "https://api.anthropic.com/v1/messages"
    headers = {
        "x-api-key": api_key,
        "anthropic-version": "2023-06-01",
        "content-type": "application/json"
    }
    
    data = {
        "model": "claude-3-5-haiku-20241022",
        "max_tokens": 8192,
        "messages": [
            {"role": "user", "content": prompt}
        ]
    }

    response = requests.post(url, headers=headers, json=data)
    return response.json()

def main():
    try:
        api_key = read_file('api_key')
        prompt = read_file('prompt4.md')
        
        result = query_claude(api_key, prompt)
        print(json.dumps(result, indent=2))
        
    except FileNotFoundError as e:
        print(f"Error: Could not find file: {e.filename}")
    except requests.RequestException as e:
        print(f"API request failed: {e}")
    except json.JSONDecodeError:
        print("Error: Invalid JSON response from API")

if __name__ == "__main__":
    main()
