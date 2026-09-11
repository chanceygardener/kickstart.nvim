local T = require 'test.helpers'
local work = require 'custom.work'

T.eq(work.parse_identifier '[ENG-245] do some engineering work', 'ENG-245', 'bracketed identifier')
T.eq(work.parse_identifier '[DATA-441] pipeline fix', 'DATA-441', 'non-ENG team key')
T.eq(work.parse_identifier '[abc-12] lowercase', 'ABC-12', 'lowercase normalized up')
T.eq(work.parse_identifier 'ENG-77 no brackets', 'ENG-77', 'unbracketed identifier')
T.eq(work.parse_identifier '[X2-9] digit in key', 'X2-9', 'digit in team key')
T.nil_(work.parse_identifier 'no ticket here', 'no identifier present')
T.nil_(work.parse_identifier '', 'empty string')
T.nil_(work.parse_identifier(nil), 'nil input')

T.done()
