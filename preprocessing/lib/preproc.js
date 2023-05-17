const util = require("util");

exports.preamble = `/* ************************************************** *
            GENERATED FILE. DO NOT EDIT.
 * ************************************************** */`;

exports.struct_utilities = `/* since you can't convert bool to uint in an expression without conditionals,
 * we add a file-level function and rely on compiler optimization
 */
function uint_of_bool(bool b) pure returns (uint u) {
  assembly { u := b }
}

uint constant ONES = type(uint).max;`;

const field_var = (_name, prop) => {
  return `${_name}_${prop}`;
};

const capitalize = (s) => s.slice(0, 1).toUpperCase() + s.slice(1);

class Field {
  constructor(data) {
    this.name = data.name;
    this.type = data.type;
    this.bits = data.bits;
    this.vars = {
      before: field_var(this.name, "before"),
      mask: field_var(this.name, "mask"),
      bits: field_var(this.name, "bits"),
    };
    // cleanup-mask: 0s at field location, 1s elsewhere
    this.mask = `~((ONES << 256 - ${this.vars.bits}) >> ${this.vars.before})`;
  }

  extract(from) {
    const uint_val = `(${from} << ${this.vars.before}) >> (256 - ${this.vars.bits})`;
    return this.from_uint(uint_val);
  }

  from_uint(uint_val) {
    if (this.type === "address") {
      return `address(uint160(${uint_val}))`;
    } else if (this.type === "bool") {
      return `((${uint_val}) > 0)`;
    } else {
      // uint by default
      return uint_val;
    }
  }

  inject(val) {
    const uint_val = this.to_uint(val);
    return `(${uint_val} << (256 - ${this.vars.bits})) >> ${this.vars.before}`;
  }

  to_uint(val) {
    if (this.type === "address") {
      return `uint(uint160(${val}))`;
    } else if (this.type === "bool") {
      return `uint_of_bool(${val})`;
    } else {
      // uint by default
      return val;
    }
  }
}

class Struct {
  // validate struct_def: correct types & sizes
  static validate(fields_def) {
    const red = (acc, field) => {
      const desc = util.inspect(field);
      if (!["uint", "address", "bool"].includes(field.type)) {
        throw new Error(
          `bad field ${desc}, only allowed types are uint,address and bool`
        );
      }
      if (field.type === "address" && field.bits !== 160) {
        throw new Error(`bad field ${desc}, addresses must have 160 bits`);
      }
      return acc + field.bits;
    };
    const bits = fields_def.reduce(red, 0);
    if (bits > 256) {
      throw new Error(
        `bad fields ${util.inspect(fields_def)}\nbitsize ${bits} > 256`
      );
    }
  }

  constructor(name, fields_def, filenamer) {
    Struct.validate(fields_def);
    this.name = name;
    this.Name = capitalize(this.name);
    this.Packed = `${this.Name}Packed`;
    this.Unpacked = `${this.Name}Unpacked`;
    this.filename = filenamer(this);

    this.fields = fields_def.map((data) => new Field(data));
  }
  unwrap(val) {
    return `${this.Packed}.unwrap(${val})`;
  }
  wrap(val) {
    return `${this.Packed}.wrap(${val})`;
  }
}

exports.make_structs = (struct_defs, filenamer) => {
  return Object.entries(struct_defs).map(([name, fields_def]) => {
    return new Struct(name, fields_def, filenamer);
  });
};
