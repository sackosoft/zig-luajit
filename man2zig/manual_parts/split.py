with open('manual.html', 'rb') as f:
    manual = f.read().decode("iso-8859-1")

DEF_SPLIT="""<hr><h3><a name="""

FUNCTIONS_START="""<h2>3.7"""
FUNCTIONS_END="""<h2>3.8"""

false_start = manual.index(FUNCTIONS_START)
actual_start = false_start + (manual[false_start:]).index(DEF_SPLIT) + len(DEF_SPLIT) #Skip to get over the first separator text
end = manual.index(FUNCTIONS_END)

functions = manual[actual_start:end]
functions = functions.replace("\n\n\n", "")
functions = functions.split(DEF_SPLIT)
functions = [DEF_SPLIT + f for f in functions if f and len(f)]

# print("First: ", functions[0])
# print("Last: ", functions[-1])

AUX_START="""<h2>4.1"""
AUX_END="""<h1>5 """

false_start = manual.index(AUX_START)
actual_start = false_start + (manual[false_start:]).index(DEF_SPLIT) + len(DEF_SPLIT) # Skip to get over the first separator text
end = manual.index(AUX_END)

aux = manual[actual_start:end]
aux = aux.replace("\n\n\n", "")
aux = aux.split(DEF_SPLIT)
aux = [DEF_SPLIT + a for a in aux if a and len(a)]

# print("AUX:")
# print("First: ", aux[0])
# print("Last: ", aux[-1])

combined_definitions = functions + aux

with open('definitions.json', 'w', encoding='utf-8') as f:
    import json
    json.dump(combined_definitions, f, indent=2)

print("Done")
