const { strict: assert } = require('node:assert');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const vm = require('node:vm');

const page = readFileSync(join(__dirname, '../merlinclash/webs/Module_merlinclash.asp'), 'utf8');
const fields = { merlinclash_links: 'https://example.invalid/sub', merlinclash_uploadrename: '' };
const alerts = [];
const requests = [];
const context = {
    $: selector => ({ val: () => fields[selector.slice(1)] }),
    E: key => ({ value: fields[key] }),
    alert: message => alerts.push(message),
    Base64: { encode: value => Buffer.from(value).toString('base64') },
    db_merlinclash: {},
    push_data: (...args) => requests.push(args)
};
context.$.trim = value => String(value ?? '').trim();
vm.createContext(context);
for (const name of ['requireConfigName', 'get_online_yaml', 'download_yaml_sel']) {
    const start = page.indexOf('        function ' + name + '(');
    assert.ok(start >= 0);
    const end = page.indexOf('\n        }', start);
    vm.runInContext(page.slice(start, end + '\n        }'.length), context);
}
for (const name of ['', '  ', '.yaml']) {
    fields.merlinclash_uploadrename = name;
    fields.merlinclash_delyamlsel = name;
    assert.equal(context.get_online_yaml(2), false);
    assert.equal(context.download_yaml_sel('downyaml'), false);
    assert.match(alerts.at(-1), /添加配置名称/);
}
assert.equal(requests.length, 0);
fields.merlinclash_uploadrename = 'Home7';
context.get_online_yaml(2);
assert.equal(requests.length, 1);
assert.equal(requests[0][2].merlinclash_uploadrename, 'Home7');
