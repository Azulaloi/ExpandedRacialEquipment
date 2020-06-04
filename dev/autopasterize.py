import sys
import time
import logging
import pyperclip
from watchdog.observers import Observer
from watchdog.events import LoggingEventHandler

fileDir = ''

def pasterize(filename):
	f = open(filename, "r")
	list = [line.rstrip('\n') for line in f]
	f.close()

	joined = ''.join(list)
	# joined.replace(" ", "")

	pyperclip.copy(joined)

class AzHandler(LoggingEventHandler):
	def __init__(self):
		super(AzHandler, self).__init__()
	def on_modified(self, event):
		if event.is_directory: return
		logging.info('pasterizing!')
		pasterize(event.src_path)
		
	def on_created(self, event):
		super(LoggingEventHandler, self).on_created(event)
	def on_deleted(self, event):
		super(LoggingEventHandler, self).on_deleted(event)
	def on_moved(self, event):
		super(LoggingEventHandler, self).on_moved(event)

if __name__ == "__main__":
	logging.basicConfig(level=logging.INFO,
						format='%(asctime)s - %(message)s',
						datefmt='%Y-%m-%d %H:%M:%S')
						
	fileDir = sys.argv[1] if len(sys.argv) > 1 else '.'
	
	
    #event_handler = LoggingEventHandler()
	event_handler = AzHandler()
	
	observer = Observer()
	observer.schedule(event_handler, fileDir, recursive=True)
	observer.start()
	try:
		while True:
			time.sleep(1)
	except KeyboardInterrupt:
		observer.stop()
	observer.join()