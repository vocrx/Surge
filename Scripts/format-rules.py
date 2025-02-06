import sys
import os


def process_and_clean(input_file):
    with open(input_file, "r", encoding="utf-8") as f:
        lines = f.readlines()

    cleaned_lines = []
    for line in lines:
        content = line.split("//")[0].strip()
        if content and not content.startswith("#"):
            cleaned_lines.append(content)

    suffixes = set()
    keywords = set()
    for line in cleaned_lines:
        if line.startswith("DOMAIN-SUFFIX,"):
            suffix = line.split(",")[1]
            suffixes.add(suffix)
        elif line.startswith("DOMAIN-KEYWORD,"):
            keyword = line.split(",")[1].lower()
            keywords.add(keyword)

    final_lines = []
    removed = set()

    for line in cleaned_lines:
        if line.startswith("DOMAIN,"):
            domain = line.split(",")[1]
            domain_lower = domain.lower()
            keyword_match = False
            for keyword in keywords:
                if keyword in domain_lower:
                    removed.add(line)
                    keyword_match = True
                    break

            if keyword_match:
                continue

            domain_parts = domain.split(".")
            for i in range(1, len(domain_parts)):
                possible_suffix = ".".join(domain_parts[i:])
                if possible_suffix in suffixes:
                    removed.add(line)
                    break
            else:
                final_lines.append(line)

        elif line.startswith("DOMAIN-SUFFIX,"):
            suffix = line.split(",")[1]
            suffix_lower = suffix.lower()
            keyword_match = False
            for keyword in keywords:
                if keyword in suffix_lower:
                    removed.add(line)
                    keyword_match = True
                    break

            if not keyword_match:
                final_lines.append(line)

        elif line.startswith("DOMAIN-KEYWORD,"):
            final_lines.append(line)

        else:
            final_lines.append(line)

    final_lines.sort()

    with open(input_file, "w", encoding="utf-8") as f:
        for line in final_lines:
            f.write(line + "\n")

    return len(removed)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("使用方法: python process_and_clean.py <文件路径>")
        sys.exit(1)

    input_file = sys.argv[1]
    if not os.path.exists(input_file):
        print(f"错误: 文件 '{input_file}' 不存在")
        sys.exit(1)

    removed_count = process_and_clean(input_file)
    print(f"已删除 {removed_count} 个重复的条目")
