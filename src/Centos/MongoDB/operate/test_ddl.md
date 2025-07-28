// 切换到或创建新数据库
use testdb1


// 验证当前数据库
db.getName()

// 创建users集合并插入文档
db.users.insertMany([
  {
    name: "Alice",
    age: 28,
    email: "alice@example.com",
    skills: ["JavaScript", "Node.js"],
    created_at: new Date()
  },
  {
    name: "Bob",
    age: 32,
    email: "bob@example.com",
    skills: ["Python", "Django"],
    created_at: new Date()
  },
  {
    name: "Charlie",
    age: 25,
    email: "charlie@example.com",
    skills: ["Java", "Spring"],
    created_at: new Date()
  }
])

// 创建products集合并插入文档
db.products.insertMany([
  {
    name: "Laptop",
    category: "Electronics",
    price: 999.99,
    stock: 15,
    tags: ["computer", "gadget"]
  },
  {
    name: "Smartphone",
    category: "Electronics",
    price: 699.99,
    stock: 30,
    tags: ["mobile", "android"]
  },
  {
    name: "Coffee Mug",
    category: "Kitchen",
    price: 12.99,
    stock: 100,
    tags: ["drinkware", "ceramic"]
  }
])

show dbs

show collections