# Blazor learning

## Summary so far

Started looking at Blazor to learn a bit more about front-end, with the ultimate goal of building my own bread baking data tracking app. Wasn't sure how far I would go so didn't take notes through my first bit of reading and tinkering, but better to start from part way than not at all!

I started diving into the deep end and after getting the scaffolding of a project stood up following the basic [getting started](https://dotnet.microsoft.com/en-us/learn/aspnet/blazor-tutorial/) guide, I spent an afternoon trying to integrate the front end with a simple web api.. I've forgotten where I got stuck now, but it was not successful. Decided to take a step back and walk before I run, and started instead with the [Build a to-do list with Blazor](https://learn.microsoft.com/en-gb/training/modules/build-blazor-todo-list/) tutorial. At this point, I'm half way through the [Interact with data in Blazor web apps](https://learn.microsoft.com/en-gb/training/modules/interact-with-data-blazor-web-apps/) tutorial - so picking up from here.

I'm continuing to refer to my notes from the [udemy course I completed earlier this year](https://github.com/joe-plumb-notes/udemy-dotnet-course), and [some](https://github.com/fortunkam/QuizzR) [other](https://github.com/dotnet/blazor-samples/tree/main/8.0/BlazorWebAppCallWebApi/BlazorApp/BlazorApp) [sample](https://github.com/dotnet/blazor-samples/blob/main/8.0/BlazorWebAppCallWebApi/BlazorApp/BlazorApp.Client/Pages/CallTodoWebApiCsrNamedClient.razor) repos.

## Sharing data in Blazor apps

- Several ways to share info between components - component parameters, or cascading parameters to send values from a parent to a child component. AppState is another approach which can be used to store and access values from any component in the application.
- **Component parameters** can be used when your component makes up part of/a small fragment of your whole page. 
    - Parameters are defined on the child components, and the values are set in the parent. You start by defining the component parameter in the child component, as a C# public property, decorated with the [Parameter] attribute:
    ```
    <h2>New Pizza: @PizzaName</h2>

    <p>@PizzaDescription</p>

    @code {
        [Parameter]
        public string PizzaName { get; set; }
        
        [Parameter]
        public string PizzaDescription { get; set; } = "The best pizza you've ever tasted."
    }
    ```
    - The parameters can be rendered in the HTML because they are members of the child component. We can also set default values for the parameters, like we can in our models.
    - Custom classes can be used as component parameters. For example, take this custom class:
    ```
    public class PizzaTopping
    {
        public string Name { get; set; }
        public string Ingredients { get; set; }
    }
    ```
    We can pass this class in as a parameter to a component, and use dot notation to reference the properties in the HTML:
    ```
    <h2>New Topping: @Topping.Name</h2>

    <p>Ingredients: @Topping.Ingredients</p>

    @code {
        [Parameter]
        public PizzaTopping Topping { get; set; }
    }
    ```
    - Componenet params are good when you want to pass params to the immediate child of a componenet, but get messy when you have a deep hierarchy of components, because component params aren't automatically passed to grandchildren components. To handle this, Blazor includes **cascading parameters**. 
- **Cascading parameter** values are passed using the `<CascadingValue>` tag, which specifies the information that will be cascaded to all decendets. 
    ```
    @page "/specialoffers"

    <h1>Special Offers</h1>

    <CascadingValue Name="DealName" Value="Throwback Thursday">
        <!-- Any descendant component rendered here will be able to access the cascading value. -->
    </CascadingValue>
    ```
    - The value(s) can be accessed in decended componenets by using componenet members and decorating them with the `[CascadingParameter]` attribute
    ```
    <h2>Deal: @DealName</h2>

    @code {
        [CascadingParameter(Name="DealName")]
        private string DealName { get; set; }
    }
    ```
    - Objects can be passed as cascading parameters to address more complex requirements.
- **AppState** is another approach to sharing information between components. 
    > You create a class that defines the properties you want to store, and register it as a scoped service. In any component where you want to set or use the AppState values, you inject the service, and then you can access its properties. Unlike component parameters and cascading parameters, values in AppState are available to all components in the application, even components that aren't children of the component that stored the value
    - So consider the below class which stores number of sales:
    ```
    public class PizzaSalesState
    {
        public int PizzasSoldToday { get; set; }
    }
    ```
    - You would add this class as a scoped service in the `Program.cs` file
    ```
    ...
    // Add services to the container
    builder.Services.AddRazorPages();
    builder.Services.AddServerSideBlazor();

    // Add the AppState class
    builder.Services.AddScoped<PizzaSalesState>();
    ...
    ```
    - And then access this value by injecting the service into the component and accessing the properties:
    ```
    @page "/"
    @inject PizzaSalesState SalesState

    <h1>Welcome to Blazing Pizzas</h1>

    <p>Today, we've sold this many pizzas: @SalesState.PizzasSoldToday</p>

    <button @onclick="IncrementSales">Buy a Pizza</button>

    @code {
        private void IncrementSales()
        {
            SalesState.PizzasSoldToday++;
        }
    }
    ```
- In the excersize, I created a new `OrderState` service, in the `Services` folder of the project:
    ```
    namespace BlazingPizza.Services
    {
        public class OrderState
        {
            public bool ShowingConfigureDialog { get; private set; }
            public Pizza ConfiguringPizza { get; private set; }
            public Order Order { get; private set; } = new Order();

            public void ShowConfigurePizzaDialog(PizzaSpecial special)
            {
                ConfiguringPizza = new Pizza()
                {
                    Special = special,
                    SpecialId = special.Id,
                    Size = Pizza.DefaultSize,
                    Toppings = new List<PizzaTopping>(),
                };

                ShowingConfigureDialog = true;
            }

            public void CancelConfigurePizzaDialog()
            {
                ConfiguringPizza = null;

                ShowingConfigureDialog = false;
            }

            public void ConfirmConfigurePizzaDialog()
            {
                Order.Pizzas.Add(ConfiguringPizza);
                ConfiguringPizza = null;

                ShowingConfigureDialog = false;
            }
        }
    }

    ```
- This service was then added to the Program using the `builder.Services.AddScoped` method `builder.Services.AddScoped<OrderState>();`
- Which was then injected into the razor page to access the object and methods
    ```
    @using BlazingPizza.Services
    @inject OrderState OrderState
    ```
- I also added some additional `EventCallback` parameters to the `ConfigurePizzaDialog` component, which enabled interaction between the click events on the buttons in the page, and the functions in the `ConfigurePizzaDialog` component
    - Parameters in the component code:
    ```
        [Parameter] public EventCallback OnCancel { get; set; }
        [Parameter] public EventCallback OnConfirm { get; set; }
    ```
    - Connecting to the parameters from the `index.razor` where the component is instantiated
    ```
    <ConfigurePizzaDialog 
    Pizza="OrderState.ConfiguringPizza" 
    OnCancel="OrderState.CancelConfigurePizzaDialog"
    OnConfirm="OrderState.ConfirmConfigurePizzaDialog" />
    ```