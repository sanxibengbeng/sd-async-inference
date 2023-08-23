import os
from configparser import ConfigParser

schedulerConfig = ConfigParser()
schedulerConfig.read('conf.ini')

if __name__ == "__main__":
    print(os.path.abspath('conf.ini'))
    print('sections:', schedulerConfig.sections())
    print(schedulerConfig.get("aws", "region"))