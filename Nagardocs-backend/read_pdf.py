import fitz
import sys

try:
    doc = fitz.open(r"c:\Users\mahes\Desktop\NagarDocs\nagardocs_structure (1).pdf")
    text = ""
    for page in doc:
        text += page.get_text() + "\n"
    print(text[:4000])  # print first 4000 characters to get the structure
except Exception as e:
    print("Error reading PDF:", e)
