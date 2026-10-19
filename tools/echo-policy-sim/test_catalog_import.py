import unittest
from catalog_import import parse, render

ROW='[101] = { maxStack = 80, classMask = 1, minLevel = 1, quality = 0, groupId = 2, requiredSpell = 0, comment = "A", families = { "Tank", "Melee DPS" } },'
def source(row=ROW): return 'ProjectEbonhold.PerkDatabase = {\n'+row+'\n}\nerror("must not execute")'

class ImportTests(unittest.TestCase):
    def test_data_only(self):
        rows=parse(source());self.assertEqual(rows[101]['roles'],['Tank','Melee DPS'])
        self.assertEqual(rows[101]['maxStack'],80)
        self.assertNotIn('error',render(rows,'abc'))
    def test_no_roles(self):
        rows=parse(source(ROW.replace(', families = { "Tank", "Melee DPS" }','')))
        self.assertEqual(rows[101]['roles'],[])
    def test_inline_close(self):
        self.assertEqual(len(parse(source().replace(',\n}',',}'))),1)
    def test_fail_closed(self):
        for bad in (source(ROW+'\n'+ROW),source(ROW.replace('80','math.random()')),
                    source(ROW.replace('"Tank", "Melee DPS"','"Tank",, "Melee DPS"')),
                    source(ROW.replace('"Tank", "Melee DPS"','"Tank", "Tank"')),
                    source(ROW.replace('quality = 0','quality = 9')),source().replace('\n}\n','\n'),
                    source(ROW+'\n[102] = getRow()')):
            with self.assertRaises(ValueError): parse(bad)

if __name__=='__main__': unittest.main()
