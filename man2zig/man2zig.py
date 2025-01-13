import sys
import ziggen

try:
    from bs4 import BeautifulSoup
except ImportError:
    print("Error: BeautifulSoup4 is not installed. Install it with: pip install beautifulsoup4")
    exit(1)

try:
    import lxml
except ImportError:
    print("Error: lxml is not installed. Install it with: pip install lxml")
    exit(1)


def parse_html(file_path: str) -> BeautifulSoup:
    try:
        with open(file_path, 'rb') as f:
            soup = BeautifulSoup(f, 'lxml')
        return soup
    except FileNotFoundError:
        print(f"Error: File not found: {file_path}")
        return None
    except Exception as e:
        print(f"Error parsing HTML: {str(e)}")
        return None

def main() -> int:
    if len(sys.argv) < 2:
        print("Error: Please provide the path to the Lua 5.1 Manual")
        print("Usage: python script.py <lua_manual>")
        return 1

    path_to_manual = sys.argv[1]
    manual = parse_html(path_to_manual)
    if not manual:
        return 1

    ziggen.generate_zig_artifacts(manual);
    return 0

if __name__ == "__main__":
    sys.exit(main())
