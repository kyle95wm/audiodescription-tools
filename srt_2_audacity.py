import sys

if len(sys.argv) < 3:
	print("Usage: python3 2audacity.py input_file output_file")
	print("WARNING: Will clobber output file")
	exit()


input_file = sys.argv[1]
output_file = sys.argv[2]

try:
	file1 = open(input_file, 'r')
	lines = file1.readlines()
	file1.close()
except:
	print("Unable to open file " + input_file)
	exit()

counter = 1
output_lines = []

for line in lines:
	line = line.strip()
	fields = line.split('\t')

	# Fields 1, Fields 2, Counter + Fields[0:15] (ie. add counter and truncate to 15 characters)
	printline = '\t'.join([fields[0],fields[1],(str(counter) + " " + fields[2][:15])+'\n'])
	output_lines.append(printline)
	counter += 1

try:
	with open(output_file, "w") as output_file:
		for line in output_lines:
			output_file.write(line)
except:
	print("Unable to open file " + output_file)
	exit()
