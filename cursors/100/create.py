for i in range (101):
	with open ("azreticle" + str(i) + ".cursor", "w+") as f:
		f.write('{')
		f.write('\n"offset" : [15, 15],')
		f.write('\n"image" : "/cursors/100/azreticle100.png:' + str(i) + '"')
		f.write('\n}')