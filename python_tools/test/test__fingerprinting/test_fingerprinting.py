import os
import shutil
import unittest
import pandas as pd

from python_tools.workflow_tools.qc.fingerprinting import (
    read_csv,
    plot_genotyping_matrix
)


class FingerprintingTestCase(unittest.TestCase):

    def setUp(self):
        """
        Set some constants used for testing

        :return:
        """
        # Allow us to use paths relative to the current directory's tests
        # os.chdir('test__noise_plots')

        # Set up test outputs directory
        os.mkdir('./test_output')

    def tearDown(self):
        """
        Remove test outputs after each test

        :return:
        """
        shutil.rmtree('./test_output')

        # Move back up to main test dir
        # os.chdir('..')

    def test_plot_genotpying_matrix(self):
        geno_compare = read_csv('./test_data/Geno_compare.txt')
        title_file = pd.read_csv('./test_data/title_file.txt')
        plot_genotyping_matrix(geno_compare, './test_output/', title_file)

        geno_expected = pd.read_csv('./expected_output/Match_status.txt', sep='\t')
        geno_actual = pd.read_csv('./test_output/Match_status.txt', sep='\t')
        assert geno_expected.equals(geno_actual)

if __name__ == '__main__':
    unittest.main()
